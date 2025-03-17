#! /bin/bash 

module use /mnt/beegfs/$USER/spack-stack_1.7.0/envs/mpas-bundle/install/modulefiles/Core

module load stack-gcc/9.4.0
module load openmpi/4.1.1   

module load boost/1.84.0
module load jedi-cmake/1.4.0
module load python/3.10.13
module load c-blosc/1.21.5
module load libbsd/0.11.7  
module load qhull/2020.2
module load ca-certificates-mozilla/2023-05-30
module load libmd/1.0.4   
module load snappy/1.1.10
module load cmake/3.23.1 
module load libxcrypt/4.4.35  
module load sqlite/3.43.2
module load curl/8.4.0 
module load nghttp2/1.57.0  
module load stack-openmpi/4.1.1
module load ecbuild/3.7.2 
module load openblas/0.3.24 
module load stack-python/3.10.13
module load eigen/3.4.0 
module load tar/1.34
module load gcc-runtime/9.4.0
module load py-pip/23.1.2 
module load udunits/2.2.28
module load gettext/0.21.1
module load py-pycodestyle/2.11.0  
module load util-linux-uuid/2.38.1
module load gmake/4.3  
module load py-setuptools/63.4.3 
module load zlib-ng/2.1.5
module load gsl-lite/0.37.0
module load py-wheel/0.41.2  
module load zstd/1.5.2
module load atlas/0.36.0
module load fftw/3.3.10  
module load nccmp/1.9.0.1   
module load parallelio/2.6.2
module load eckit/1.24.5 
module load fiat/1.2.0   
module load netcdf-c/4.9.2
module load ectrans/1.2.0 
module load gptl/8.1.1  
module load netcdf-fortran/4.6.1
module load fckit/0.11.0   
module load hdf5/1.14.3 
module load parallel-netcdf/1.12.3

module list
