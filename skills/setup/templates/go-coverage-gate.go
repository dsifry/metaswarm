// go-coverage-gate.go — metaswarm's blocking coverage gate for Go projects.
//
// Written to .metaswarm/go-coverage-gate.go by metaswarm /setup and run as the
// enforcement command:
//
//	go run .metaswarm/go-coverage-gate.go [packages...]   (default ./...)
//
// `go test` has no coverage-threshold flag, so this gate runs
// `go test -coverprofile=coverage.out <packages>`, counts covered statements
// in the profile, and exits 1 when coverage is below the thresholds in
// .coverage-thresholds.json. It reads that file every run, so the file stays
// the single source of truth. It compares exact statement counts: the
// one-decimal total from `go tool cover -func` would show 2,499 of 2,500
// statements as 100.0%.
//
// Go reports statement coverage only. The `lines` and `statements` thresholds
// are both enforced against it; `branches` and `functions` are reported as not
// enforced. The leading dot in .metaswarm keeps this file out of ./... builds.
//
// Standard library only. Safe to delete if you uninstall metaswarm.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

const (
	configFile  = ".coverage-thresholds.json"
	profileFile = "coverage.out"
)

type config struct {
	Thresholds map[string]*float64 `json:"thresholds"`
}

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(pkgs []string) int {
	thresholds, err := readThresholds(configFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "coverage gate: %v\n", err)
		return 1
	}

	if len(pkgs) == 0 {
		pkgs = []string{"./..."}
	}
	args := append([]string{"test", "-coverprofile=" + profileFile}, pkgs...)
	cmd := exec.Command("go", args...)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "coverage gate: go test failed: %v\n", err)
		return 1
	}

	covered, total, err := countStatements(profileFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "coverage gate: %v\n", err)
		return 1
	}
	return judge(thresholds, covered, total)
}

func readThresholds(path string) (map[string]*float64, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("cannot read %s (run from the project root): %w", path, err)
	}
	var c config
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, fmt.Errorf("%s is not valid JSON: %w", path, err)
	}
	if c.Thresholds == nil {
		return nil, fmt.Errorf("%s has no \"thresholds\" object", path)
	}
	if c.Thresholds["lines"] == nil && c.Thresholds["statements"] == nil {
		return nil, fmt.Errorf("%s sets neither thresholds.lines nor thresholds.statements, so there is nothing to enforce for Go", path)
	}
	return c.Thresholds, nil
}

// countStatements reads a Go cover profile. Each line after the "mode:" header
// is "file:startLine.startCol,endLine.endCol numStmts count". A block can appear
// more than once (for example with -coverpkg), so blocks are merged by
// position and a block counts as covered if any occurrence ran.
func countStatements(path string) (covered, total int64, err error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, 0, fmt.Errorf("cannot read cover profile %s: %w", path, err)
	}
	defer f.Close()

	type block struct {
		stmts int64
		hit   bool
	}
	blocks := map[string]*block{}
	order := []string{}
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1024*1024), 1024*1024)
	lineNo := 0
	for sc.Scan() {
		lineNo++
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "mode:") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) != 3 {
			return 0, 0, fmt.Errorf("%s:%d: malformed cover profile line %q", path, lineNo, line)
		}
		stmts, err1 := strconv.ParseInt(fields[1], 10, 64)
		count, err2 := strconv.ParseInt(fields[2], 10, 64)
		if err1 != nil || err2 != nil || stmts < 0 {
			return 0, 0, fmt.Errorf("%s:%d: malformed cover profile line %q", path, lineNo, line)
		}
		b, ok := blocks[fields[0]]
		if !ok {
			b = &block{stmts: stmts}
			blocks[fields[0]] = b
			order = append(order, fields[0])
		}
		if count > 0 {
			b.hit = true
		}
	}
	if err := sc.Err(); err != nil {
		return 0, 0, fmt.Errorf("cannot read cover profile %s: %w", path, err)
	}
	for _, k := range order {
		total += blocks[k].stmts
		if blocks[k].hit {
			covered += blocks[k].stmts
		}
	}
	return covered, total, nil
}

func judge(thresholds map[string]*float64, covered, total int64) int {
	if total == 0 {
		fmt.Println("coverage gate: no Go statements found in the cover profile; nothing to enforce.")
		return 0
	}
	pct := float64(covered) * 100 / float64(total)
	fmt.Printf("coverage gate: %d of %d statements covered (%s%%)\n", covered, total, strconv.FormatFloat(pct, 'f', -1, 64))

	failed := false
	for _, dim := range []string{"lines", "statements"} {
		t := thresholds[dim]
		if t == nil {
			continue
		}
		// covered/total >= t/100, cross-multiplied so no rounded percentage is
		// compared; exact for whole-number thresholds.
		ok := float64(covered)*100 >= *t*float64(total)
		if ok {
			fmt.Printf("  PASS %s: %s%% >= %s%% (Go statement coverage)\n", dim, fmtPct(pct), fmtPct(*t))
		} else {
			// Statements still needed to reach the threshold.
			need := int64(0)
			for float64(covered+need)*100 < *t*float64(total) {
				need++
			}
			fmt.Printf("  FAIL %s: %s%% < %s%% (Go statement coverage; cover %d more statement(s))\n", dim, fmtPct(pct), fmtPct(*t), need)
			failed = true
		}
	}
	for _, dim := range []string{"branches", "functions"} {
		if t := thresholds[dim]; t != nil {
			fmt.Printf("  NOT ENFORCED %s (%s%%): Go reports statement coverage only\n", dim, fmtPct(*t))
		}
	}
	if failed {
		fmt.Println("coverage gate: FAILED")
		return 1
	}
	fmt.Println("coverage gate: passed")
	return 0
}

// fmtPct shows enough precision that a failing value never prints as equal to
// the threshold (99.96 stays 99.96, not 100.0).
func fmtPct(v float64) string {
	return strconv.FormatFloat(v, 'f', -1, 64)
}
