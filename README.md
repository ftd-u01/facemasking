# facemasking

Docker container for WashU facemasking code, from

https://nrg.wustl.edu/software/face-masking/


## Dependencies and licensing

The container uses dcm2nii, Matlab Runtime and FSL. Users must abide by the
licensing conditions of each package.


## Building the container

Before the docker build, [download the
software](https://download.nrg.wustl.edu/pub/FaceMasking/MaskFace.10.15.2018.nomatlab.lin64.zip)
and unzip into this directory.


## Parameter choices

For reference, the call in the picsl-xnat pipeline uses the following options:

```
-z -b 1 -e 1 -s 1.0 -t -1 -um 0 -roi 0 -ver 0
```

The first option must be a DICOM input directory; multiple inputs may be
specified as a comma separated list.


## Citation

If using this algorithm, please cite

Milchenko, M. V. & Marcus, D. (2012). Obscuring surface anatomy in volumetric imaging data. Neuroinformatics. doi: 10.1007/s12021-012-9160-3
