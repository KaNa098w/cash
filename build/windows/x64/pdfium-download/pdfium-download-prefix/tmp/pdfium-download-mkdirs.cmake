# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file Copyright.txt or https://cmake.org/licensing for details.

cmake_minimum_required(VERSION ${CMAKE_VERSION}) # this file comes with cmake

# If CMAKE_DISABLE_SOURCE_CHANGES is set to true and the source directory is an
# existing directory in our source tree, calling file(MAKE_DIRECTORY) on it
# would cause a fatal error, even though it would be a no-op.
if(NOT EXISTS "D:/Programs/cash/build/windows/x64/pdfium-src")
  file(MAKE_DIRECTORY "D:/Programs/cash/build/windows/x64/pdfium-src")
endif()
file(MAKE_DIRECTORY
  "D:/Programs/cash/build/windows/x64/pdfium-build"
  "D:/Programs/cash/build/windows/x64/pdfium-download/pdfium-download-prefix"
  "D:/Programs/cash/build/windows/x64/pdfium-download/pdfium-download-prefix/tmp"
  "D:/Programs/cash/build/windows/x64/pdfium-download/pdfium-download-prefix/src/pdfium-download-stamp"
  "D:/Programs/cash/build/windows/x64/pdfium-download/pdfium-download-prefix/src"
  "D:/Programs/cash/build/windows/x64/pdfium-download/pdfium-download-prefix/src/pdfium-download-stamp"
)

set(configSubDirs Debug;Release;MinSizeRel;RelWithDebInfo)
foreach(subDir IN LISTS configSubDirs)
    file(MAKE_DIRECTORY "D:/Programs/cash/build/windows/x64/pdfium-download/pdfium-download-prefix/src/pdfium-download-stamp/${subDir}")
endforeach()
if(cfgdir)
  file(MAKE_DIRECTORY "D:/Programs/cash/build/windows/x64/pdfium-download/pdfium-download-prefix/src/pdfium-download-stamp${cfgdir}") # cfgdir has leading slash
endif()
