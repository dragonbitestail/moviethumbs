#!/bin/bash

# Movie Montage
#
# Dependencies:
# zentity, imagemagick, ffmpegthumbnailer, trash-cli
#
# Initial test environment:
# * Ubuntu 12.04.5 LTS
# * XFCE 4.8  (Window Manager)
# * Thunar
# * Deployed as a Thunar file manager "custom action"
#

DEBUG=false

# Default Sequence start and step values for Snapshots. E.g. percentage into
# file where to start and how far from current step to next step (%) up to 100.
SEQ_START=1
SEQ_STEP=7
SEQ_THUMB_SIZE=480
SEQ_GETVALS=true
if [[ $1 == "-q" ]] || [[ $0 =~ q$ ]]; then
	SEQ_GETVALS=false
fi

SETTINGS_GLOBAL=false

DO_PURGE_QUERY=true  # Query whether to do purge at least once
DO_PURGE=false       # Do not purge temp. snapshots dir by default.

# Messages
SNAPS_ERROR=""

# Commands
LOG_FILE=montage.log
sleep=/bin/sleep
grep=/bin/grep
xargs=/usr/bin/xargs
find=/usr/bin/find
file=/usr/bin/file
mkdir=/bin/mkdir
rmdir=/bin/rmdir
mv=/bin/mv
echo=/bin/echo
sleep=/bin/sleep
dname=/usr/bin/dirname
bname=/usr/bin/basename
printf=/usr/bin/printf
ffmpegthumbnailer=/usr/bin/ffmpegthumbnailer
montage=/usr/bin/montage
tr=/usr/bin/tr
ls=/bin/ls
stat=/usr/bin/stat
cut=/usr/bin/cut
touch=/usr/bin/touch
trash=/usr/bin/trash-put
yad=/usr/bin/yad

SELECT_FILE_DIR=""
FILEPATHS=( )

# Select Movie file:

if [[ $# -gt 0 ]]; then
  PWD=$( pwd )

  if [ -d "$1" ];then # First arg is directory. Assume we will be selecting files using dialog.
    SELECT_FILE_DIR="$1"
    shift
    $DEBUG && $echo "arg 1 is directory = \"$SELECT_FILE_DIR\""
  fi
  FILEPATHS=( "$@" )
fi

ZENITY_FILEPATHS=( )
if [ -d "$SELECT_FILE_DIR" ];then
  IFS_pre=$IFS
  IFS="|"
  ZENITY_FILEPATHS=( $( $yad --file-selection --filename="$SELECT_FILE_DIR" --multiple --heightr=300 --width=1200) )
  $echo "ZENITY_FILEPATHS = ${ZENITY_FILEPATHS[@]}"
  IFS=$IFS_pre
  FILEPATHS=( "${FILEPATHS[@]}" "${ZENITY_FILEPATHS[@]}" )

fi

$DEBUG && $echo "FILEPATHS following optional yad select: ${FILEPATHS[@]}"

if [[ ${#FILEPATHS[@]} -lt 1 ]]; then  # Not enough args, bail out.
  $yad  --info --text="No file/s selected. Exiting..."
  exit 1
fi
if [[ ${#FILEPATHS[@]} -gt 1 ]]; then  # Multiple files, Query whether to apply settings to all files
  if yad --question --title="Sequence settings" --text="Apply same settings to all?"; then
    SETTINGS_GLOBAL=true
  fi
fi

# For each file in $FILEPATHS do
#   * Test the file for compliance w/ our rules
#   * cd to the directory where our selected files reside.
#   * Create a temp dir, as child-dir of cwd, based on the current file selected in our loop
#   * Query for snapshot sequence vals.
#   * Create set of snapshot stills from current selected movie file and write to temp dir.
#   * Create Montage image from the stills based on name of the movie file
#   * Prompt to perform cleanup of the temp dir.
for FILEPATH in "${FILEPATHS[@]}"; do

  # Testing file
  FILEINFO=$( $file "$FILEPATH" )
  if $echo $FILEINFO | $cut -d':' -f2 | \
     $grep -qiE 'video|asf|mkv|mpeg|mpg|RealMedia|flv|avi|mp4|webm' \
     > /dev/null 2>&1 ; then
    $DEBUG && $echo "Passed file check with info: $FILEINFO"
  else
    $yad  --info --text="The \"file\" command does not recognize $FILEPATH \
      as a video file.\n\nFile Info: $FILEINFO"
    #exit 1
    continue
  fi

  infile_mtime="$($stat "$FILEPATH"  | $grep Modify:  | $cut -d ':' -f 2- | $cut -d ' ' -f2-)"
  $DEBUG && $echo "[DEBUG] \"$FILEPATH\" mtime: $infile_mtime"

  FILENAME=$( $bname "$FILEPATH" )

  START_DIR=$( $dname "$FILEPATH" )
  cd "$START_DIR"

  SNAP_DIR=$( $echo -n montage_$FILENAME | $tr -c "[:alnum:]" "." )

  $mkdir -p $SNAP_DIR

  cd $SNAP_DIR

    # Unfortunately forms does not seem to support setting default values
    # which results in multiple prompts.
  if $SEQ_GETVALS; then
    SEQ_START=$( $yad --entry --text="Start % (0-100)" --entry-text=$SEQ_START )
    SEQ_STEP=$( $yad --entry --text="Step from start to 100" --entry-text=$SEQ_STEP )

    SEQ_THUMB_SIZE=$( $yad --entry --text="Pixel width size of thumbs" --entry-text=$SEQ_THUMB_SIZE )

  fi

  if $SETTINGS_GLOBAL; then  # When true, allow it to only happen on first loop iteration.
    SEQ_GETVALS=false
  fi

  $echo "In \"$( pwd  )\" w/ Sequence start / step: $SEQ_START /  $SEQ_STEP" >> $LOG_FILE 2>&1

  # Ensure $? is 0 prior to snapshots loop
  true
  for i in $( seq $SEQ_START $SEQ_STEP 100  ); do
    pnum=$( $printf "%03d" $i )
 
    if [ ! -f "${SNAP_DIR}_${pnum}.jpg" ]; then
      thumbs_cmd="$ffmpegthumbnailer -f -q10 -i ../\"$FILENAME\"  -o ${SNAP_DIR}_${pnum}.jpg -t\"${i}%\" -s\"${SEQ_THUMB_SIZE}\"   >> $LOG_FILE 2>&1"
      $echo  "$thumbs_cmd"   >> $LOG_FILE 2>&1
      eval $thumbs_cmd
      $sleep 0.2
    else
      $echo  "\"${SNAP_DIR}_${pnum}.jpg\" already exists. Skipping..."   >> $LOG_FILE 2>&1
    fi
    $echo $i  # Echo the snapshot percentage just completed for yad

    EXIT_VAL=$?

    $echo  "Current exit value = $EXIT_VAL" >> $LOG_FILE 2>&1
    if [ "$EXIT_VAL" != "0" ];then
      $echo  "exiting. Assume Canceled."   >> $LOG_FILE 2>&1
      break
    fi

  done | $yad --progress --auto-close

  # SNAPS_ERROR val eaten by pipe while $? has a non-0 exit value (although not the val from within the pipe).
  # $? being used for now.  If run into issues explore PIPESTATUS.
  # $echo  "SNAPS_ERROR = \"$SNAPS_ERROR\" following for loop|yad..."   >> $LOG_FILE 2>&1
  # $echo  "$? = \"$?\" following for loop|yad..."   >> $LOG_FILE 2>&1
  if [ "$?" != "0" ];then
    SNAPS_ERROR="Snapshots Canceled/Errored..."
  fi

  BASEFILE=${FILENAME%.*}

  # Create a montage sheet from all the snapshots:

  $montage -background Black -pointsize 28 -stroke White -fill Yellow -gravity south -title "${FILENAME%.*}" -geometry '1x1+8+8<'  ${SNAP_DIR}_*.jpg   ../"$BASEFILE".jpg  >> $LOG_FILE 2>&1
  $sleep 0.4

  $touch -d "$infile_mtime" -m ../"$BASEFILE".jpg

  # Prompt to Cleanup our SNAP_DIR
  # BUG on NAS drive:
  # "/bin/ls: cannot access *.jpg: No such file or directory"

  if $DO_PURGE_QUERY; then
    if $yad  --question --text="${SNAPS_ERROR}\nPurge the Snapshots directory \"$SNAP_DIR\"?" ; then
      DO_PURGE=true
    else
      DO_PURGE=false
    fi
  fi

  if $SETTINGS_GLOBAL; then
    DO_PURGE_QUERY=false
  fi

  if $DO_PURGE; then
    for f in $( $find . -name "*.jpg" );do
      $trash $f
    done
    $trash ./${LOG_FILE}
    cd ..
    $rmdir $SNAP_DIR
  fi

done
