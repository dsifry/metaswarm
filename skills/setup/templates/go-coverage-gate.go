// go-coverage-gate.go — metaswarm's blocking coverage gate for Go projects.
//
// Written to .metaswarm/go-coverage-gate.go by metaswarm /setup and run as the
// enforcement command:
//
//	go run .metaswarm/go-coverage-gate.go [go test flags and packages...]   (default ./...)
//
// `go test` has no coverage-threshold flag, so this gate runs
// `go test -coverprofile=coverage.out <arguments>`, counts covered statements
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
	"math/big"
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
	Thresholds map[string]json.RawMessage `json:"thresholds"`
}

// threshold is a configured percentage, kept as the exact decimal written in
// .coverage-thresholds.json so no rounding can lower it.
type threshold struct {
	text string   // as written, for messages
	rat  *big.Rat // exact value
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

func readThresholds(path string) (map[string]*threshold, error) {
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
	out := map[string]*threshold{}
	for _, dim := range []string{"lines", "statements", "branches", "functions"} {
		raw, ok := c.Thresholds[dim]
		if !ok {
			continue
		}
		var n json.Number
		if err := json.Unmarshal(raw, &n); err != nil {
			return nil, fmt.Errorf("%s: thresholds.%s is not a number: %s", path, dim, raw)
		}
		r, ok := new(big.Rat).SetString(n.String())
		if !ok || r.Sign() < 0 || r.Cmp(big.NewRat(100, 1)) > 0 {
			return nil, fmt.Errorf("%s: thresholds.%s must be a number between 0 and 100, got %s", path, dim, n)
		}
		out[dim] = &threshold{text: n.String(), rat: r}
	}
	if out["lines"] == nil && out["statements"] == nil {
		return nil, fmt.Errorf("%s sets neither thresholds.lines nor thresholds.statements, so there is nothing to enforce for Go", path)
	}
	return out, nil
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

func judge(thresholds map[string]*threshold, covered, total int64) int {
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
		// covered/total >= t/100 with exact rationals: no rounded percentage
		// or float product (99.9*41000 rounds up in float64) is ever compared.
		required := new(big.Rat).Mul(t.rat, big.NewRat(total, 100)) // statements needed
		if new(big.Rat).SetInt64(covered).Cmp(required) >= 0 {
			fmt.Printf("  PASS %s: %s%% >= %s%% (Go statement coverage)\n", dim, fmtPct(pct), t.text)
		} else {
			// Statements still needed: ceil(required) - covered.
			q, m := new(big.Int).QuoRem(required.Num(), required.Denom(), new(big.Int))
			if m.Sign() > 0 {
				q.Add(q, big.NewInt(1))
			}
			need := q.Int64() - covered
			fmt.Printf("  FAIL %s: %s%% < %s%% (Go statement coverage; cover %d more statement(s))\n", dim, fmtPct(pct), t.text, need)
			failed = true
		}
	}
	for _, dim := range []string{"branches", "functions"} {
		if t := thresholds[dim]; t != nil {
			fmt.Printf("  NOT ENFORCED %s (%s%%): Go reports statement coverage only\n", dim, t.text)
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
