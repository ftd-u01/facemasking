#!/bin/bash

source /etc/fsl/5.0/fsl.sh
source ${MASKFACE_HOME}/maskface_setup.sh

${MASKFACE_HOME}/bin/mask_face_nomatlab $*
