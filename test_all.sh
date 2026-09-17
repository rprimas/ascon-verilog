# Run tests for all variants of the Ascon core
set -o pipefail
results=()
overall_status=0

for variant in V1 V2 V3 V4 V5 V6; do
    make clean
    make VARIANT="$variant"
    status=$?
    if [ "$status" -eq 0 ]; then
        results+=("$variant: PASS")
    else
        results+=("$variant: FAIL (exit status $status)")
        overall_status=1
    fi
done

echo
echo "Test results summary:"
printf '  %s\n' "${results[@]}"
exit "$overall_status"
