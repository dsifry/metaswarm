#!/bin/bash
set -euo pipefail

# --- Defaults ---
input_tokens=0
output_tokens=0
model=""

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --input-tokens)
            input_tokens="$2"
            shift 2
            ;;
        --output-tokens)
            output_tokens="$2"
            shift 2
            ;;
        --model)
            model="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter passed: $1"
            exit 1
            ;;
    esac
done

# --- Validate Arguments ---
if [[ -z "$model" || "$input_tokens" -eq 0 || "$output_tokens" -eq 0 ]]; then
    echo "Error: --input-tokens, --output-tokens, and --model are required." >&2
    exit 1
fi

# --- Model Pricing (per 1 million tokens) ---
input_cost_rate=""
output_cost_rate=""

case "$model" in
    "gpt-5.3-codex")
        input_cost_rate="1.50"
        output_cost_rate="6.00"
        ;;
    "gemini-pro")
        input_cost_rate="1.25"
        output_cost_rate="5.00"
        ;;
    *)
        echo "Error: Unknown model '$model'." >&2
        exit 1
        ;;
esac

# --- Cost Calculation ---
input_cost_per_token=$(awk "BEGIN {print $input_cost_rate / 1000000}")
output_cost_per_token=$(awk "BEGIN {print $output_cost_rate / 1000000}")

total_input_cost=$(awk "BEGIN {print $input_tokens * $input_cost_per_token}")
total_output_cost=$(awk "BEGIN {print $output_tokens * $output_cost_per_token}")

estimated_usd=$(awk "BEGIN {print $total_input_cost + $total_output_cost}")

# --- JSON Output ---
cat <<EOF
{
  "model": "$model",
  "input_tokens": $input_tokens,
  "output_tokens": $output_tokens,
  "estimated_usd": $estimated_usd
}
EOF
