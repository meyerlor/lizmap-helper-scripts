@ECHO OFF
SETLOCAL EnableDelayedExpansion

REM ====================================
REM TIFF to COG Converter
REM Converts TIFF files to Cloud Optimized GeoTIFF with JPEG compression
REM ====================================

ECHO.
ECHO ====================================
ECHO TIFF to COG Converter
ECHO ====================================
ECHO.

REM Get input folder path
SET /P input_folder=Path to folder with TIFF files:
IF "%input_folder%"=="" (
    ECHO Error: No input path specified.
    PAUSE
    EXIT /B 1
)

REM Check if input folder exists
IF NOT EXIST "%input_folder%" (
    ECHO Error: Input folder does not exist.
    PAUSE
    EXIT /B 1
)

REM Get output filename only (will be created in same directory as CMD file)
SET /P output_filename=Output filename (e.g. Orthofoto.tif):
IF "%output_filename%"=="" (
    ECHO Error: No filename specified.
    PAUSE
    EXIT /B 1
)

REM Build full output path in same directory as CMD file
SET output_file=%~dp0%output_filename%

REM Create temporary files in TEMP directory
SET temp_list=%TEMP%\tiff_list_%RANDOM%.txt
SET temp_vrt=%TEMP%\temp_vrt_%RANDOM%.vrt

ECHO.
ECHO Creating list of TIFF files...
dir "%input_folder%\*.tif" /b /s > "%temp_list%"

REM Check if any TIFF files were found
FOR %%A IN ("%temp_list%") DO SET file_size=%%~zA
IF %file_size% EQU 0 (
    ECHO Error: No TIFF files found in specified folder.
    DEL "%temp_list%"
    PAUSE
    EXIT /B 1
)

ECHO.
ECHO Creating VRT...
C:\OSGeo4W\bin\gdalbuildvrt.exe -resolution average -a_srs EPSG:25832 -r nearest -allow_projection_difference -srcnodata 255 -input_file_list "%temp_list%" "%temp_vrt%"

IF ERRORLEVEL 1 (
    ECHO Error creating VRT.
    DEL "%temp_list%" "%temp_vrt%" 2>NUL
    PAUSE
    EXIT /B 1
)

ECHO.
ECHO Converting to COG...
ECHO This may take a while depending on data size...
C:\OSGeo4W\bin\gdal_translate.exe "%temp_vrt%" "%output_file%" -a_srs EPSG:25832 -of COG -co BLOCKSIZE=512 -co COMPRESS=JPEG -co QUALITY=75 -co BIGTIFF=YES -co NUM_THREADS=ALL_CPUS -co OVERVIEW_RESAMPLING=AVERAGE -co OVERVIEW_COUNT=12

IF ERRORLEVEL 1 (
    ECHO Error during conversion.
    DEL "%temp_list%" "%temp_vrt%"
    PAUSE
    EXIT /B 1
)

REM Clean up temporary files
DEL "%temp_list%" "%temp_vrt%"

ECHO.
ECHO ====================================
ECHO Conversion completed successfully!
ECHO Output file: %output_file%
ECHO ====================================
ECHO.
PAUSE
