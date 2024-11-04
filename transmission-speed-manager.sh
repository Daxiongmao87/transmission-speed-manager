#!/bin/bash

# Set up flags with default values
DOWNLOAD_PERCENTAGE=25
SAMPLE_SIZE=5
TRANSMISSION_URLS=()
MINIMUM_SPEED_THRESHOLD=0

# Function to display help
function display_help() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -u, --transmission-urls         Transmission URLs (comma-separated, required))"
  echo "  -p, --download-percentage       Percentage of average download speed to set (default: 25))"
  echo "  -s, --sample-size               Number of speed test samples to take (default: 5))"
  echo "  -m, --minimum-speed-threshold   Minimum download speed threshold in KB/s (default: 0))"
  echo "  -h, --help                      Display this help message"
  exit 0
}

# Parse flags
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -u|--transmission-urls)
      IFS=',' read -r -a TRANSMISSION_URLS <<< "$2"
      shift 2
      ;;
    -p|--download-percentage)
      DOWNLOAD_PERCENTAGE="$2"
      shift 2
      ;;
    -s|--sample-size)
      SAMPLE_SIZE="$2"
      shift 2
      ;;
    -m|--minimum-speed-threshold)
      MINIMUM_SPEED_THRESHOLD="$2"
      shift 2
      ;;
    -h|--help)
      display_help
      ;;
    *)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

# Ensure transmission URLs are provided
if [ ${#TRANSMISSION_URLS[@]} -eq 0 ]; then
  echo "Error: --transmission-urls is required."
  exit 1
fi

# Conduct speed tests
echo "Conducting Speed Test $SAMPLE_SIZE times"

TOTAL_DOWNLOAD=0
for ((i=1; i<=$SAMPLE_SIZE; i++))
do
    SPEED_TEST_RESULTS=$(curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 - --secure)
    SPEED_TEST_DOWNLOAD=$(echo "$SPEED_TEST_RESULTS" | grep 'Download:') # Output is: Download: ##.## <G/M/K>bit/s
    echo "Download Speed for test $i: $SPEED_TEST_DOWNLOAD"
    RAW_DOWNLOAD=0
    UNIT=$(echo $SPEED_TEST_DOWNLOAD | awk '{print substr($0, length($0)-5, length($0))}') # Extract the unit (G/M/K)bit/s
    VALUE=$(echo $SPEED_TEST_DOWNLOAD | awk '{print $2}' | sed 's/[a-zA-Z]*//g') # Extract the numeric value

    if [ "$UNIT" == "Gbit/s" ]; then
        RAW_DOWNLOAD=$(echo "$VALUE * 125000" | bc) # Convert Gbit/s to KB/s
    elif [ "$UNIT" == "Mbit/s" ]; then
        RAW_DOWNLOAD=$(echo "$VALUE * 125" | bc) # Convert Mbit/s to KB/s
    elif [ "$UNIT" == "Kbit/s" ]; then
        RAW_DOWNLOAD=$(echo "$VALUE / 8" | bc) # Convert Kbit/s to KB/s
    fi
    TOTAL_DOWNLOAD=$(echo "$TOTAL_DOWNLOAD + $RAW_DOWNLOAD" | bc)
done

# Calculate average download speed
AVERAGE_DOWNLOAD=$(echo "scale=2; $TOTAL_DOWNLOAD / $SAMPLE_SIZE" | bc)
echo "Average Download Speed: $AVERAGE_DOWNLOAD KB/s"

# Calculate target download speed
TARGET_DOWNLOAD=$(echo "scale=2; $AVERAGE_DOWNLOAD / (100 / $DOWNLOAD_PERCENTAGE)" | bc)
echo "Target Download Speed: $TARGET_DOWNLOAD KB/s (${DOWNLOAD_PERCENTAGE}%)"

# Check if the average download speed is below the minimum threshold
if (( $(echo "$AVERAGE_DOWNLOAD < $MINIMUM_SPEED_THRESHOLD" | bc -l) )); then
  echo "Average download speed is below the minimum threshold of $MINIMUM_SPEED_THRESHOLD KB/s. Setting download speed to 0 KB/s."
  SPLIT_TARGET_DOWNLOAD=0
else
  # Split the target download speed among the servers
  SPLIT_TARGET_DOWNLOAD=$(echo "scale=2; $TARGET_DOWNLOAD / ${#TRANSMISSION_URLS[@]}" | bc)
  SPLIT_TARGET_DOWNLOAD=$(printf "%.0f" $SPLIT_TARGET_DOWNLOAD) # Round to the nearest whole number
fi

# Set download speed for each transmission URL
for URL in "${TRANSMISSION_URLS[@]}"
do
    echo "Setting download speed for $URL to $SPLIT_TARGET_DOWNLOAD KB/s"
    transmission-remote $URL -d $SPLIT_TARGET_DOWNLOAD
done
