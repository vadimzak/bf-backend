#!/bin/bash

# Check if at least one argument (the inner script name) is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <inner_script> [script_params...]"
    exit 1
fi

# Extract the inner script name and its parameters
INNER_SCRIPT="$1"
shift  # Remove the first argument to get only the inner script's params
INNER_PARAMS=("$@")

# Check if the inner script exists
if [ ! -f "$INNER_SCRIPT" ]; then
    echo "Error: Script '$INNER_SCRIPT' not found!"
    exit 1
fi

# Check if the inner script is executable
if [ ! -x "$INNER_SCRIPT" ]; then
    echo "Warning: '$INNER_SCRIPT' is not executable. Attempting to run with bash..."
fi

# Create a temporary file for capturing execution log
LOG_FILE=$(mktemp /tmp/script_execution_XXXXXX.log)

echo "Executing: $INNER_SCRIPT ${INNER_PARAMS[*]}"
echo "Log file: $LOG_FILE"
echo "----------------------------------------"

# Execute the inner script and capture output
if [ -x "$INNER_SCRIPT" ]; then
    # If executable, run directly
    "$INNER_SCRIPT" "${INNER_PARAMS[@]}" 2>&1 | tee "$LOG_FILE"
else
    # If not executable, run with bash
    bash "$INNER_SCRIPT" "${INNER_PARAMS[@]}" 2>&1 | tee "$LOG_FILE"
fi

# Capture the exit status
EXIT_STATUS=${PIPESTATUS[0]}

if [ $EXIT_STATUS -ne 0 ]; then
    echo "----------------------------------------"
    echo "Script failed with exit code: $EXIT_STATUS"
    echo "Opening Claude Code for debugging..."
    
    # Create a prompt for Claude Code
    PROMPT="The bash script '$INNER_SCRIPT' failed with exit code $EXIT_STATUS.

Script parameters: ${INNER_PARAMS[*]}

Execution log:
$(cat "$LOG_FILE")

Please:
1. Analyze the error and identify the root cause
2. Provide 2 different solutions to fix the problem
3. Explain the pros and cons of each solution"
    
    # Check if claude-code is available
    if command -v claude &> /dev/null; then
        # Create a temporary file with the prompt
        PROMPT_FILE=$(mktemp /tmp/claude_prompt_XXXXXX.txt)
        echo "$PROMPT" > "$PROMPT_FILE"
        
        # Open Claude Code with the script and prompt
        echo "Opening Claude Code with debugging information..."
        claude -p "$INNER_SCRIPT" --prompt-file "$PROMPT_FILE"
        
        # Clean up prompt file
        rm -f "$PROMPT_FILE"
    else
        echo "Error: 'claude' command not found!"
        echo "Please ensure Claude Code is installed and in your PATH."
        echo ""
        echo "Debug information saved to: $LOG_FILE"
        echo ""
        echo "Prompt that would have been sent to Claude Code:"
        echo "================================================"
        echo "$PROMPT"
    fi
else
    echo "----------------------------------------"
    echo "Script completed successfully!"
    # Clean up log file on success
    rm -f "$LOG_FILE"
fi

exit $EXIT_STATUS