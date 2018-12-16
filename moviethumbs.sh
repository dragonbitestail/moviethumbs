#!/bin/bash

# File Manager script -> Montage Movie File
# Tested environment:
# * Ubuntu 12.04.5 LTS 
# * XFCE 4.8  (Window Manager)
# * 
# * Deployed as a Thunar file manager "custom action"

# NOTES:
# Thunar
#  Removed the file patterns: *.rm;*.avi;*.mov;*.mpg;*.mpeg;*.mp4;*.ogm;*.wmv;*.flv
#  as they were preventing option from showing up when selecting a directory.


# DONE: Modify to support selection of multiple file or starting directory:
#
# * Check arg count
# * If arg count > 1, prompt to whether to apply seq start /step to all files.
# * After args checks, wrap everything in outer loop for each file.
#
# Caveats:
# * Recursion not supported
# * Only single directory selection tested
# * Directories containing mix of video and non-vid files not tested

# DONE: Determine why getting empty "LOG_FILE" in dir. above SNAP_DIR.
# ANS.: We don't switch to SNAP_DIR until into the inner loop for ea. file
#       we are dealing with.
# RESOLUTION: Only write to log in SNAP_DIR. as only SNAP_DIR gets cleaned up.

# TODO: Determine if problems with paths are due to spaces:
# Possible solution is to use "read" in while loop instead of
# "for" loop which prevent control of IFS.
#  http://www.linuxquestions.org/questions/programming-9/bash-cp-and-filename-with-spaces-woes-453181/
#
# Don't believe this is happening since I switched to using the trash-cli command.
# But, don't really remember where in the codes the problem was...


# Dependencies:
# zentity, imagemagick, ffmpegthumbnailer, trash-cli

# 
DEBUG=false

# Default Sequence start and step values for Snapshots. E.g. percentage into
# file where to start and how far from current step to next step (%) up to 100.
SEQ_START=0
SEQ_STEP=5
SEQ_THUMB_SIZE=500
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
trash=/usr/bin/trash-put
zenity=/usr/bin/zenity

SELECT_FILE_DIR=""
FILEPATHS=( )
# Select Movie file:
#if [ "$1" == "" ]; then
if [[ $# -gt 0 ]]; then
  PWD=$( pwd )

  if [ -d "$1" ];then # First arg is directory. Assume we will be selecting files using dialog.
    SELECT_FILE_DIR="$1"
    shift
    if $DEBUG; then 
      $echo "arg 1 is directory = \"$SELECT_FILE_DIR\""
    fi
  fi
  #FILEPATH="${PWD}/${1}"
  #FILEPATH="${1}"
  FILEPATHS=( "$@" )
fi


ZENITY_FILEPATHS=( )
if [ -d "$SELECT_FILE_DIR" ];then
  IFS_pre=$IFS
  IFS="|"
  ZENITY_FILEPATHS=( $( $zenity --file-selection --filename="$SELECT_FILE_DIR" --multiple ) )
  $echo "ZENITY_FILEPATHS = ${ZENITY_FILEPATHS[@]}"
  IFS=$IFS_pre
  FILEPATHS=( "${FILEPATHS[@]}" "${ZENITY_FILEPATHS[@]}" )

fi

if $DEBUG; then
  $echo "FILEPATHS following optional zenity select: ${FILEPATHS[@]}"
fi

if [[ ${#FILEPATHS[@]} -lt 1 ]]; then  # Not enough args, bail out.
  $zenity  --info --text="No file/s selected. Exiting..."
  exit 1
fi
if [[ ${#FILEPATHS[@]} -gt 1 ]]; then  # Multiple files, Query whether to apply settings to all files
  if zenity --question --title="Sequence settings" --text="Apply same settings to all?"; then
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
  if $echo $FILEINFO | $grep -qviE 'video|asf|mkv|mpeg|mpg|RealMedia|flv|avi|mp4' > /dev/null 2>&1 ; then
    $zenity  --info --text="The \"file\" command does not recognize $FILEPATH as a video file.\n\nFile Info: $FILEINFO\n\nExiting..."
    exit 1
  fi
  
  FILENAME=$( $bname "$FILEPATH" )
  
  START_DIR=$( $dname "$FILEPATH" )
  cd "$START_DIR"
  
  SNAP_DIR=$( $echo -n montage_$FILENAME | $tr -c "[:alnum:]" "." )
  
  $mkdir -p $SNAP_DIR
  
  cd $SNAP_DIR
  
    # Unfortunately forms does not seem to support setting default values
    # which results in multiple prompts. 
  if $SEQ_GETVALS; then
    SEQ_START=$( $zenity --entry --text="Start % (0-100)" --entry-text=$SEQ_START )
    SEQ_STEP=$( $zenity --entry --text="Step from start to 100" --entry-text=$SEQ_STEP )

    SEQ_THUMB_SIZE=$( $zenity --entry --text="Pixel width size of thumbs" --entry-text=$SEQ_THUMB_SIZE )

  fi


  if $SETTINGS_GLOBAL; then  # When true, allow it to only happen on first loop iteration.
    #SETTINGS_GLOBAL=false
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
    $echo $i  # Echo the snapshot percentage just completed for zenity
  
    EXIT_VAL=$?
  
    $echo  "Current exit value = $EXIT_VAL" >> $LOG_FILE 2>&1
    if [ "$EXIT_VAL" != "0" ];then
      $echo  "exiting. Assume Canceled."   >> $LOG_FILE 2>&1
      break
    fi 
  
  done | $zenity --progress --auto-close
  
  # SNAPS_ERROR val eaten by pipe while $? has a non-0 exit value (although not the val from within the pipe).
  # $? being used for now.  If run into issues explore PIPESTATUS.
  # $echo  "SNAPS_ERROR = \"$SNAPS_ERROR\" following for loop|zenity..."   >> $LOG_FILE 2>&1
  # $echo  "$? = \"$?\" following for loop|zenity..."   >> $LOG_FILE 2>&1
  if [ "$?" != "0" ];then
    SNAPS_ERROR="Snapshots Canceled/Errored..."
  fi 
  
  BASEFILE=${FILENAME%.*}
  
  # Create a montage sheet from all the snapshots:
  
  $montage -background Black -pointsize 28 -stroke White -fill Yellow -gravity south -title "${FILENAME%.*}" -geometry '1x1+8+8<'  ${SNAP_DIR}_*.jpg   ../"$BASEFILE".jpg  >> $LOG_FILE 2>&1
  $sleep 0.4
  
  # Prompt to Cleanup our SNAP_DIR
  # BUG on NAS drive:
  # "/bin/ls: cannot access *.jpg: No such file or directory"
    
  if $DO_PURGE_QUERY; then
    if $zenity  --question --text="${SNAPS_ERROR}\nPurge the Snapshots directory \"$SNAP_DIR\"?" ; then
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
