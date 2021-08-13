#/bin/bash
#$ -S /bin/bash
set -e -x

#set -e -x


#######################################################################
#
#  Program:   LongASHS (Longitudinal ASHS pipeline for T1w MRI)
#  Module:    $Id$
#  Language:  BASH Shell Script
#  Copyright (c) 2020 Long Xie, University of Pennsylvania
#
#  This file is the implementation of the longitudinal pipeline of ASHS for T1w MRI
#
#######################################################################

# some basic functions
function usage()
{
  cat <<-USAGETEXT
LongASHST1_main: Longitudinal ASHS pipeline for T1w MRI
  usage:
    LongASHST1_main [options]
            
  required options:
    -n str            Subject ID. The script will look for scan information in the information 
                      CSV file.
    -g dir            Directory to the ASHS-T1 output directory of the baseline T1w MRI scan.
    -l dir            Directory to the baseline left side ASHS-T1 automatic segmentation.
    -r dir            Directory to the baseline right side ASHS-T1 automatic segmentation.
    -i dir            Directory to the csv file with information of all the time points 
                      written down in the following format:

                        id,scandate_TP1,directory_to_TP1_T1,bl,include
                        id,scandate_TP2,directory_to_TP2_T1,fu,include
                        id,scandate_TP3,directory_to_TP3_T1,fu,include
                        ...

                      Every line contains information of one time point starting with the 
                      baseline (bl) and then the follow up (fu) time points. The scandate 
                      needs to be in format of YYYY-MM-DD.

    -w path           Output directory
                
  optional:
    -T                Tidy mode. Cleans up files once they are unneeded.
    -h                Print help
    -s integer        Run only one stage (see below); also accepts range (e.g. -s 1-3).
                      Stages:
                        1: Perform super resolution to all timepoints
                        2: Perform ALOHA between baseline and each of the followup time points
                        3: Quantify change rates
                        4: Clean up and reorganize results

USAGETEXT
}

# Dereference a link - different calls on different systems
function dereflink ()
{
  if [[ $(uname) == "Darwin" ]]; then
    local SLTARG=$(readlink $1)
    if [[ $SLTARG ]]; then
      echo $SLTARG
    else
      echo $1
    fi
  else
    readlink -m $1
  fi
}

# Print usage by default
if [[ $# -lt 1 ]]; then
  echo "Try $0 -h for more information."
  exit 2
fi

# Read the options
while getopts "n:g:l:r:i:w:s:hT" opt; do
  case $opt in

    n) id=$OPTARG;;
    g) BLASHSRUNDIR=$OPTARG;;
    l) BLASHSLSEG=$OPTARG;;
    r) BLASHSRSEG=$OPTARG;;
    i) INFOCSV=$OPTARG;;
    w) OUTDIR=$OPTARG;;
    s) STAGE_SPEC=$OPTARG;;
    T) DELETETMP=1;;
    h) usage; exit 0;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;

  esac
done

##############################################
# Setup environment
# Software PATH
#export ASHS_ROOT=/data/picsl/longxie/pkg/ashs/ashs-fast-beta
export PATH=$PATH:$ASHS_ROOT/bin
C3DPATH=$ASHS_ROOT/ext/Linux/bin
#MATLAB_BIN=/share/apps/matlab/R2017a/bin/matlab

BASEDIR=$(dirname "$0")
BASEDIR=$(readlink -sf $BASEDIR)
CODEDIR=$BASEDIR
BINDIR=$BASEDIR/bin
MATLABCODEDIR=$BASEDIR/matlabcode
export ALOHA_ROOT=$BASEDIR/bin/aloha

if [[ $DELETETMP == "" ]]; then
  DELETETMP="0"
fi

WORKDIR=$OUTDIR/work
SRDIR=$WORKDIR/SR
ALOHADIR=$WORKDIR/ALOHA
QUANDIR=$WORKDIR/quantification
DUMPDIR=$OUTDIR/dump
TMPDIR=$DUMPDIR/tmp
mkdir -p $TMPDIR

# parameters




# Check if the required parameters were passed in
echo "id    : ${id?    "Subject id was not specified. See $0 -h"}"
echo "ASHS run directory    : ${BLASHSRUNDIR?    "ASHS run directory was not specified. See $0 -h"}"
echo "INFOCSV    : ${INFOCSV?    "CSV file with information of all the timepoints was not specified. See $0 -h"}"
echo "Baseline left side ASHS segmentation    : ${BLASHSLSEG?    "Baseline left side ASHS segmentation was not specified. See $0 -h"}"
echo "Baseline right side ASHS segmentation    : ${BLASHSRSEG?    "Baseline right side ASHS segmentation was not specified. See $0 -h"}"
echo "OutputDir    : ${OUTDIR?    "CSV file with information of all the timepoints was not specified. See $0 -h"}"


# Check the root dir
if [[ ! $ASHS_ROOT ]]; then
  echo "Please set ASHS_ROOT to the ASHS root directory before running $0"
  exit -2
elif [[ $ASHS_ROOT != $(dereflink $ASHS_ROOT) ]]; then
  echo "ASHS_ROOT must point to an absolute path, not a relative path"
  exit -2
fi
ASHSEXTBIN=$ASHS_ROOT/ext/Linux/bin

# Check the root dir
if [[ ! $MATLAB_BIN ]]; then
  echo "Please set MATLAB_BIN to the ASHS root directory before running $0"
  exit -2
fi


# Convert the work directory to absolute path
mkdir -p ${OUTDIR?}
OUTDIR=$(cd $OUTDIR; pwd)
if [[ ! -d $OUTDIR ]]; then
  echo "Work directory $OUTDIR cannot be created"
  exit -2
fi
mkdir -p $WORKDIR
mkdir -p $DUMPDIR

# Redirect output/error to a log file in the dump directory
LOCAL_LOG=$(date +longashs_main.o%Y%m%d_%H%M%S)
mkdir -p $DUMPDIR
exec > >(tee -i $DUMPDIR/$LOCAL_LOG)
exec 2>&1

# Write into the log the arguments and environment
echo "longashs_main execution log"
echo "  timestamp:   $(date)"
echo "  invocation:  $0 $@"
echo "  directory:   $PWD"
echo "  environment:"

# get some basic information
TPCSV=$WORKDIR/info.csv
cat $INFOCSV | grep ^$id | grep ",include" |  grep ",bl" > $TPCSV

# check number of baseline
if [[ $(cat $TPCSV | wc -l) -gt 1 ]]; then
  echo "There are more than one baseline scans specified."
  exit -2
fi
if [[ $(cat $TPCSV | wc -l) -eq 0 ]]; then
  echo "No baseline scans specified."
  exit -2
fi

cat $INFOCSV | grep ^$id | grep ",include" | grep ",fu" >> $TPCSV
NTP=$(cat $TPCSV | wc -l)
id=$(cat $TPCSV | head -n 1 | cut -d, -f1)
BLscandate=$(cat $TPCSV | head -n 1 | cut -d, -f2)

if [[ $NTP -lt 2 ]]; then
  echo "At least two time points need to be provided."
  exit -2
fi

# check for duplicated scandates
USCANDATES=($(cat $TPCSV | awk -F, '{print $2}' | uniq))
if [[ ${#USCANDATES[*]} -lt $NTP ]]; then
  echo "Found duplicated scandates."
  exit -2
fi

STAGE_NAMES=(\
  "Perform super resolution to all timepoints" \
  "Perform ALOHA between baseline and each of the followup time points" \
  "Quantify change rates." \
  "Clean up and reorganize results.")

# Set the start and end stages
if [[ $STAGE_SPEC ]]; then
  STAGE_START=$(echo $STAGE_SPEC | awk -F '-' '$0 ~ /^[0-9]+-*[0-9]*$/ {print $1}')
  STAGE_END=$(echo $STAGE_SPEC | awk -F '-' '$0 ~ /^[0-9]+-*[0-9]*$/ {print $NF}')
  if [[ $STAGE_END -gt 4 ]]; then
    STAGE_END=4
  fi
else
  STAGE_START=1
  STAGE_END=4
fi

#############################################
function main()
{
  # Run the various stages
  for ((STAGE=$STAGE_START; STAGE<=$STAGE_END; STAGE++)); do

    # The desription of the current stage
    STAGE_TEXT=${STAGE_NAMES[STAGE-1]}
    echo "****************************************"
    echo "Starting stage $STAGE: $STAGE_TEXT"
    echo "****************************************"

    case $STAGE in

      1) SR;;
      2) Aloha;;
      3) Quantification;;
      4) CleanUp;;

    esac

  done

  #echo "Step 2/4: Perform ALOHA between baseline and each of the followup time points"
  #Aloha

  #echo "Step 3/4: Quantify change rates."
  #Quantification

  #echo "Step 4/4: Clean up and reorganize results."
  #CleanUp

  echo "Done!"
}

#############################################
function SR()
{
  mkdir -p $SRDIR

  for ((i=0;i<$NTP;i++)); do

    idx=$(printf %03d $i)
    line=$(cat $TPCSV | head -n $((i+1)) | tail -n 1)
    scandate=$(echo $line | cut -d, -f2)
    T1=$(echo $line | cut -d, -f3)
    EXCLUDE=$(echo $line | cut -d, -f5)

    if [[ ! -f $T1 ]]; then
      echo "Can not find T1 scan on $scandate ($T1)."
      exit -2
    fi
 
    if [[ $i == "0" ]]; then
      if [[ -f $BLASHSRUNDIR/tse.nii.gz ]]; then
        cp $BLASHSRUNDIR/tse.nii.gz $SRDIR/${id}_${scandate}_denoised_SR.nii.gz
        continue
      fi
    else
      if [[ $EXCLUDE == "exclude" ]]; then
        continue
      fi
    fi

    if [[ ! -f $SRDIR/${id}_${scandate}_denoised_SR.nii.gz ]]; then

    # perform denoising
    if [[ ! -f $TMPDIR/${id}_${scandate}_denoised.nii.gz ]]; then
    $ASHSEXTBIN/NLMDenoise \
      -i $T1 \
      -o $TMPDIR/${id}_${scandate}_denoised.nii.gz
    fi

    orient_code=$($ASHSEXTBIN/c3d $T1 -info | cut -d ';' -f 5 | cut -d ' ' -f 5)
    if [[ $orient_code == "Oblique," ]]; then
      orient_code=$($ASHSEXTBIN/c3d $T1 -info | cut -d ';' -f 5 | cut -d ' ' -f 8)
    fi
    
    # change orientation
    $ASHSEXTBIN/c3d \
      $TMPDIR/${id}_${scandate}_denoised.nii.gz \
      -swapdim RPI \
      -o $TMPDIR/${id}_${scandate}_denoised.nii.gz

    # perform SR
    $ASHSEXTBIN/NLMUpsample \
      -i $TMPDIR/${id}_${scandate}_denoised.nii.gz \
      -o $TMPDIR/${id}_${scandate}_denoised_SR.nii.gz \
      -lf 2 1 2

    # generate final SR
    $ASHSEXTBIN/c3d \
      $TMPDIR/${id}_${scandate}_denoised_SR.nii.gz \
      -swapdim $orient_code \
      -clip 0 inf \
      -o $SRDIR/${id}_${scandate}_denoised_SR.nii.gz

  fi
  done
}

#############################################
function Aloha()
{
  BLIMG=$SRDIR/${id}_${BLscandate}_denoised_SR.nii.gz
  mkdir -p $ALOHADIR

  for ((i=1;i<$NTP;i++)); do

    idx=$(printf %03d $i)
    line=$(cat $TPCSV | head -n $((i+1)) | tail -n 1)
    scandate=$(echo $line | cut -d, -f2)
    EXCLUDE=$(echo $line | cut -d, -f5)

    if [[ $EXCLUDE == "exclude" ]]; then
      continue
    fi

    # directories
    FWIMG=$SRDIR/${id}_${scandate}_denoised_SR.nii.gz
    TPALOHADIR=$ALOHADIR/${BLscandate}_to_${scandate}
    mkdir -p $TPALOHADIR

    if [[ ! -f $TPALOHADIR/results/volumes_left.txt || ! -f $TPALOHADIR/results/volumes_right.txt ]]; then

    # run aloha
    $ASHSEXTBIN/c3d \
      $BLASHSLSEG \
      -replace 1 999 2 999 10 999 11 999 12 999 13 999 \
      -thresh 999 999 1 0 \
      -o $TPALOHADIR/bl_seg_left.nii.gz

    $ASHSEXTBIN/c3d \
      $BLASHSRSEG \
      -replace 1 999 2 999 10 999 11 999 12 999 13 999 \
      -thresh 999 999 1 0 \
      -o $TPALOHADIR/bl_seg_right.nii.gz
   
    # run aloha using the whole MTL
    $ALOHA_ROOT/scripts/aloha_main.sh \
      -b $BLIMG \
      -f $FWIMG \
      -r $TPALOHADIR/bl_seg_left.nii.gz \
      -s $TPALOHADIR/bl_seg_right.nii.gz \
      -w $TPALOHADIR/ \
      -t 1-4 
    fi
    # run aloha for each subregion
    for sub in AHippo PHippo Hippo ERC BA35 BA36 PHC; do

      if [[ ! -f $TPALOHADIR/results_${sub}/volumes_left.txt || ! -f $TPALOHADIR/results_${sub}/volumes_right.txt ]]; then

        if [[ $sub == "ERC" ]]; then
          label=(10 10)
        elif [[ $sub == "BA35" ]]; then
          label=(11 11)
        elif [[ $sub == "BA36" ]]; then
          label=(12 12)
        elif [[ $sub == "PHC" ]]; then
          label=(13 13)
        elif [[ $sub == "AHippo" ]]; then
          label=(1 1)
        elif [[ $sub == "PHippo" ]]; then
          label=(2 2)
        elif [[ $sub == "Hippo" ]]; then
          label=(1 2)
        fi

        TPALOHASUBDIR=$TPALOHADIR/tmp/aloha_${sub}
        rm -rf $TPALOHASUBDIR
        mkdir -p $TPALOHASUBDIR/results
        ln -sf $TPALOHADIR/deformable $TPALOHASUBDIR/deformable
        ln -sf $TPALOHADIR/init $TPALOHASUBDIR/init
        ln -sf $TPALOHADIR/global $TPALOHASUBDIR/global
        ln -sf $TPALOHADIR/dump $TPALOHASUBDIR/dump
        ln -sf $TPALOHADIR/final $TPALOHASUBDIR/final

        $ASHSEXTBIN/c3d $BLASHSLSEG \
          -thresh ${label[0]} ${label[1]} 1 0 \
          -o $TPALOHASUBDIR/bl_seg_left.nii.gz

        $ASHSEXTBIN/c3d $BLASHSRSEG \
          -thresh ${label[0]} ${label[1]} 1 0 \
          -o $TPALOHASUBDIR/bl_seg_right.nii.gz

        $ALOHA_ROOT/scripts/aloha_main.sh \
          -b $BLIMG \
          -f $FWIMG \
          -r $TPALOHASUBDIR/bl_seg_left.nii.gz \
          -s $TPALOHASUBDIR/bl_seg_right.nii.gz \
          -w $TPALOHASUBDIR \
          -t 4

        rm -rf $TPALOHADIR/results_${sub}
        mv $TPALOHASUBDIR/results \
           $TPALOHADIR/results_${sub}

      fi
    done
  done
}

#############################################
function Quantification()
{
  mkdir -p $QUANDIR

  # construct spreadsheet for quantification
  header="ID,scandate,TPType,Exc,datediff,ALOHA_success,L_QA_NCC,R_QA_NCC"
  for side in L R; do
    for sub in AHippo PHippo Hippo ERC BA35 BA36 PHC; do
      header="$header,${side}_${sub}_VOL_BL,${side}_${sub}_VOL_FU"
    done
  done
  echo $header > $QUANDIR/measurements.csv

  # get measurements
  for ((i=1;i<$NTP;i++)); do

    idx=$(printf %03d $i)
    line=$(cat $TPCSV | head -n $((i+1)) | tail -n 1)
    scandate=$(echo $line | cut -d, -f2)
    TPType=$(echo $line | cut -d, -f4)
    EXCLUDE=$(echo $line | cut -d, -f5)
    if [[ $EXLUDE == "exclude" ]]; then
      continue
    fi
    date_diff=$(( \
      ($(date -d $scandate +%s) - \
      $(date -d $BLscandate +%s) )/(60*60*24) ))
    outrow="$id,$scandate,$TPType,$EXCLUDE,$date_diff"
    TPALOHADIR=$ALOHADIR/${BLscandate}_to_${scandate}
    EXIST=1
    
    QAMEASURE=""
    RAWMEASURE=""
    for side in L R; do

      if [[ $side == "L" ]]; then
          fullside="left"
        else
          fullside="right"
        fi

      # perform QA measure
      $BINDIR/mesh2img -f \
        -vtk $TPALOHADIR/results/blmptrim_seg_${fullside}_tohw.vtk \
        -a 0.3 0.3 0.3 4 \
        $TMPDIR/blmptrim_seg_${fullside}_tohw.nii.gz

      MASK=$TMPDIR/blmptrim_seg_${fullside}_tohw_mask10vox.nii.gz
      $ASHSEXTBIN/c3d  $TPALOHADIR/deformable/blmptrim_${fullside}_to_hw.nii.gz \
        $TMPDIR/blmptrim_seg_${fullside}_tohw.nii.gz \
        -int 0 -reslice-identity \
        -dilate 1 10x10x10vox \
        -o $MASK

      NCOR=$($ASHSEXTBIN/c3d \
        $MASK -as MASK \
        $TPALOHADIR/deformable/blmptrim_${fullside}_to_hw.nii.gz \
        -int 0 -reslice-identity \
        -push MASK -multiply -popas IMG1 \
        -push MASK \
        $TPALOHADIR/deformable/fumptrim_om_${fullside}to_hw.nii.gz \
        -int 0 -reslice-identity \
        -push MASK -multiply \
        -push IMG1 \
        -ncor | cut -d = -f 2)

      QAMEASURE="$QAMEASURE,$NCOR"

      # extract raw measure
      for sub in AHippo PHippo Hippo ERC BA35 BA36 PHC; do
        TPALOHASUBDIR=$TPALOHADIR/results_${sub}
        if [[ $side == "L" ]]; then
          fullside="left"
        else
          fullside="right"
        fi
        if [[ -f $TPALOHASUBDIR/volumes_${fullside}.txt ]]; then
          MEA=$(cat $TPALOHASUBDIR/volumes_${fullside}.txt)
          MEA="${MEA// /,}"
          BL=$(echo $MEA | cut -d , -f 1)
          FU=$(echo $MEA | cut -d , -f 2)
        else
          EXIST=0
          BL=""
          FU=""
        fi
        RAWMEASURE="$RAWMEASURE,$BL,$FU"
      done
    done

    # output row
    echo "$outrow,${EXIST}${QAMEASURE}${RAWMEASURE}" >> $QUANDIR/measurements.csv

  done

  # compute annualized atrophy rate
  $MATLAB_BIN -nojvm -nosplash -nodesktop <<-MATCODE
  addpath('$MATLABCODEDIR');
  quantifyAtrophyRate('$QUANDIR/measurements.csv','$QUANDIR/longitudinal_measurements_allTP.csv');
MATCODE
}

#############################################
function CleanUp()
{
  # copy result CSV to output directory
  cp $QUANDIR/measurements.csv \
     $OUTDIR/measurements_individual_timepoints.csv
  cp $QUANDIR/longitudinal_measurements_allTP.csv \
     $OUTDIR/longitudinal_measurements_all_timepoints.csv

  # copy files for QA purpose
  mkdir -p $OUTDIR/QA
  # get measurements
  for ((i=1;i<$NTP;i++)); do

    idx=$(printf %03d $i)
    line=$(cat $TPCSV | head -n $((i+1)) | tail -n 1)
    scandate=$(echo $line | cut -d, -f2)
    TPType=$(echo $line | cut -d, -f4)
    EXCLUDE=$(echo $line | cut -d, -f5)
    TPALOHADIR=$ALOHADIR/${BLscandate}_to_${scandate}
    QATPALOHADIR=$OUTDIR/QA/${BLscandate}_to_${scandate}
    if [[ ! -d $TPALOHADIR ]]; then
      continue
    fi

    # copy the files for QA
    mkdir -p $QATPALOHADIR/deformable
    for side in left right; do
      cp $TPALOHADIR/deformable/blmptrim_${side}_to_hw.nii.gz \
         $QATPALOHADIR/deformable
      cp $TPALOHADIR/deformable/fumptrim_om_${side}to_hw.nii.gz \
         $QATPALOHADIR/deformable
      cp $TPALOHADIR/deformable/fumptrim_om_to_hw_warped_3d_${side}.nii.gz \
         $QATPALOHADIR/deformable
    done

  done

  # delete intermediate file if specify
  if [[ $DELETETMP == "1" ]]; then
    rm -rf $WORKDIR
    rm -rf $DUMPDIR/tmp
  fi
}


main
