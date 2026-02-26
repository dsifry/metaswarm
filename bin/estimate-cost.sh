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
input_cost_per_token=$(awk -v rate="$input_cost_rate" 'BEGIN {print rate / 1000000}')
output_cost_per_token=$(awk -v rate="$output_cost_rate" 'BEGIN {print rate / 1000000}')

total_input_cost=$(awk -v tokens="$input_tokens" -v cost="$input_cost_per_token" 'BEGIN {print tokens * cost}')
total_output_cost=$(awk -v tokens="$output_tokens" -v cost="$output_cost_per_token" 'BEGIN {print tokens * cost}')

estimated_usd=$(awk -v ic="$total_input_cost" -v oc="$total_output_cost" 'BEGIN {print ic + oc}')

# --- JSON Output ---
cat <<EOF
{
  "model": "$model",
  "input_tokens": $input_tokens,
  "output_tokens": $output_tokens,
  "estimated_usd": $estimated_usd
}
EOF
