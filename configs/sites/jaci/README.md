# JACI Site Configuration

This directory contains the machine-specific configuration files required to support the **JACI** supercomputer within the **spack-stack** framework.

These files define the local compiler toolchain, external software provided by the system, general Spack behavior, and the module generation policy adopted for this platform. Together, they establish the configuration baseline needed to create consistent, reproducible, and maintainable software environments on JACI.

## Purpose

The purpose of this directory is to centralize all configuration elements that describe the JACI software environment from the perspective of **spack-stack** site integration.

This includes:

- definition of the compiler suite available on the system;
- registration of externally provided packages and libraries;
- configuration of general Spack installation behavior;
- specification of the module system layout exposed to end users.

By keeping these files organized in a dedicated site directory, the JACI platform can be integrated in a structured way, facilitating environment creation, maintenance, validation, and future updates.

## Expected Files

The following files are expected to be maintained in this directory:

- **`compilers.yaml`**  
  Declares the compiler toolchains available on JACI, including executable paths, versions, target architecture, and compiler-specific settings required by Spack.

- **`config.yaml`**  
  Defines global Spack configuration parameters for this site, such as installation tree behavior, build settings, cache usage, and other platform-level preferences.

- **`modules.yaml`**  
  Specifies how environment modules are generated and organized for software installed through Spack, including naming conventions, hierarchy, and exposure policy for users.

- **`packages.yaml`**  
  Describes externally installed packages available on JACI, such as MPI libraries, NetCDF, HDF5, and other system-provided dependencies that should be reused instead of rebuilt by Spack.

## Scope

The contents of this directory must be limited to configurations that are specific to the **JACI** platform.

This directory should not contain:

- application-specific environment definitions;
- generic template configurations shared across multiple machines;
- temporary files, test artifacts, or local user adjustments unrelated to the site definition.

## Maintenance Guidelines

All files in this directory should reflect the actual operational state of the JACI environment. Any change in compilers, external libraries, module organization, or site policies should be evaluated and, when applicable, propagated to these configuration files.

Updates should be made with attention to:

- technical consistency with the deployed system environment;
- reproducibility of software builds;
- compatibility with the selected **spack-stack** release;
- clarity and maintainability of the site definition over time.

## Final Note

This directory represents the official **site configuration layer** for JACI within the repository. Its quality and accuracy are essential to ensure that software environments generated with **spack-stack** remain stable, reproducible, and aligned with the characteristics of the target supercomputing platform.
