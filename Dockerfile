FROM neurodebian:xenial-non-free

RUN apt-get update && \
    apt-get install -y \
              curl \
              fsl-5.0-core \
              mricron \
              wget \
              zip

ENV MASKFACE_HOME=/opt/lin64.nomatlab

COPY lin64.nomatlab ${MASKFACE_HOME} 
COPY runFacemasking.sh /opt

RUN echo "agreeToLicense=yes" > ${MASKFACE_HOME}/input.txt && \
    /opt/lin64.nomatlab/facemaskInstaller_mcr.install -mode silent -inputFile ${MASKFACE_HOME}/input.txt 

ENV MCR_HOME=/usr/local/MATLAB/MATLAB_Runtime
ENV MASKFACE_MCR_HOME=/usr/local/facemasking 

ENTRYPOINT ["/opt/runFacemasking.sh"]

CMD [""]
