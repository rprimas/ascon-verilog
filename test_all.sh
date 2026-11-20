#!/usr/bin/env bash

# Run cocotb test bench for all variants of the Ascon core
set -o pipefail
test_synthesized=${1:-0}
variants=(V1 V2 V3 V4 V5 V6)
results=()
overall_status=0

make clean
for variant in "${variants[@]}"; do
    make VARIANT="$variant"
    status=$?
    if [ "$status" -eq 0 ]; then
        results+=("$variant: simulation: PASS")
    else
        results+=("$variant: simulation: FAIL (exit status $status)")
        overall_status=1
    fi
done

if [[ "$test_synthesized" == 1 ]]; then
    for variant in "${variants[@]}"; do
        make sim cell=simple VARIANT="$variant"
        status=$?
        if [ "$status" -eq 0 ]; then
            results+=("$variant post-synthesis: PASS")
        else
            results+=("$variant post-synthesis: FAIL (exit status $status)")
            overall_status=1
        fi
    done
fi

echo
echo "Test results summary:"
printf '  %s\n' "${results[@]}"
exit "$overall_status"
