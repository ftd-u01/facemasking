#!/usr/bin/perl -w

use strict;

use Cwd 'abs_path';
use FindBin qw($Bin);
use File::Basename;
use File::Path;
use File::Spec;
use File::Temp qw/tempdir/;
use Getopt::Long;

# Get env vars

my $usage = qq{

  $0
     --session-dir
     --output-dir
     [options]

  Defaces data stored on disk under session/series/DICOM or session/series/DICOM_ORIG. This is the format
  of the data tarballs that we use locally.

  This is a wrapper for processing HCP data. Only structural scans with protocol names of
  T1w_MPR or T2w_SPC will be defaced.

  Data copied directly from an XNAT won't work because it's in a different directory structure.
  Make the backup tarball first using the scripts under /project/ftdc_hcp/rawArchive.


  Required args:

   --session-dir
     Absolute path to the session directory containing series/DICOM (or DICOM_ORIG).

   --output-dir
     Absolute path to the output base directory. Output data and QC will be placed in a
     subdirectory for the session.


  Options:

    --series
      Comma separated list of series to process. The first one will be the reference series.
      If this option is not specified, all structural series will be processed independently.
      To process a specific single series, specify it here, eg "--series 12".

  Output:

    * A zip archive with the defaced data and all other series from the session
    * Defaced NIFTI images

  Requires singularity, dcm2niix, gdcm

};


if ($#ARGV < 0) {
    print $usage;
    exit 1;
}

checkRequiredPrograms("singularity", "dcm2niix", "gdcmdump");

my ($sessionDir, $outputBaseDir, $outputDir);

my $seriesString = "";

GetOptions ("session-dir=s" => \$sessionDir,
	    "series=s" => \$seriesString,
	    "output-dir=s" => \$outputBaseDir
    )
    or die("Error in command line arguments\n");

# Remove trailing slash to not confuse basename
$sessionDir =~ s|/$||;

my $sessionLabel = basename($sessionDir);

$outputDir = "${outputBaseDir}/${sessionLabel}";

# Need absolute paths as we are using containers and moving cwd
$sessionDir = abs_path($sessionDir);
$outputDir = abs_path($outputDir);

# to avoid confusion, insist that we can create output dir
mkpath($outputDir, {verbose => 0}) or die "Cannot create output directory $outputDir\n\t";

# Remove tmpDir
my $cleanup = 1;

my $tmpDir = tempdir( "/scratch/facemasking.tmpdir.XXXXXX", CLEANUP => $cleanup );

if (!$cleanup) {
    print "Will leave tmp dir at $tmpDir \n";
}

if (! -d $tmpDir) {
    die("Cannot create temp dir");
}

# Numbers of all series to deface
my @structuralSeries = ();

my $refSeries = "";

if ($seriesString) {
    @structuralSeries = split(",", $seriesString);
    if (scalar(@structuralSeries) > 1) {
        $refSeries = $structuralSeries[0];
    }
}
else {
    # Otherwise auto detect and run each one independently
    @structuralSeries = getStructuralSeries($sessionDir);
}

print "Running defacing on series " . join(",", @structuralSeries) . "\n";

if (scalar(@structuralSeries) == 0) {
    print "Nothing to deface\n";
    exit(1);
}

# Now set up working directory with the DICOM data
foreach my $seriesLabel (@structuralSeries) {

    my $dicomSuffix = "DICOM";

    if (-d "${sessionDir}/${seriesLabel}/DICOM_ORIG") {
        $dicomSuffix = "DICOM_ORIG";
    }

    system("mkdir -p ${tmpDir}/${seriesLabel}");

    system("cp ${sessionDir}/${seriesLabel}/${dicomSuffix}/*.dcm ${tmpDir}/${seriesLabel}");
}

# Use this for container /tmp. Doesn't get used as far as I can tell
my $jobTmpDir = $ENV{'__LSF_JOB_TMPDIR__'};

# facemasking tries to make a tmpdir but then dumps all its temp stuff in cwd, so move to tmp dir
chdir("${tmpDir}");

$ENV{'SINGULARITYENV_TMPDIR'} = "/tmp";

if ($refSeries) {
    # One call for all series, with ref
    system("singularity run --cleanenv -B ${jobTmpDir}:/tmp /project/ftdc_hcp/facemasking/bin/facemasking.sif $seriesString -e 1 -b 1 -r ${refSeries}");
}
else {
    foreach my $seriesLabel (@structuralSeries) {
        system("singularity run --cleanenv -B ${jobTmpDir}:/tmp /project/ftdc_hcp/facemasking/bin/facemasking.sif $seriesLabel -e 1 -b 1");
    }
}

# facemasking.sif default output location
my $defaceDicomDir = "${tmpDir}/DICOM_DEFACED";

# Make NII for QC
my $qcDir = "${tmpDir}/defaceQC";
system("mkdir $qcDir");

system("dcm2niix -z y -o $qcDir -f %s_%i_%p $defaceDicomDir");

# ZIP archive with defaced data
# Copy data from non-structural series
my $dicomStagingDir = "${tmpDir}/allDicom";

my %structuralMap = map { $_ => 1 } @structuralSeries;

my @inputSeries = `ls $sessionDir`;
chomp(@inputSeries);

foreach my $seriesLabel (@inputSeries) {
    if (! exists($structuralMap{$seriesLabel}) ) {
        system("cp -r ${sessionDir}/${seriesLabel} $dicomStagingDir");
    }
}

system("cp -r ${defaceDicomDir}/* $dicomStagingDir");

# Zip up dicom for transfer
system("zip -j ${outputDir}/${sessionLabel}.zip `find $dicomStagingDir -type f -name '*.dcm'`");
system("cp -r $qcDir ${outputDir}");

# Need to chdir out of the tmp dir so it can be cleaned up
chdir();


sub getStructuralSeries {

    my ($inputDir) = @_;

    my @series = `ls $inputDir`;
    chomp(@series);

    my %structuralProtocols = map { $_ => 1 } ("T1w_MPR", "T2w_SPC");
    my @structuralSeries = ();

    foreach my $seriesLabel (@series) {

        my $dicomFile = `find ${inputDir}/${seriesLabel} -type f -name "*.dcm" -print -quit`;
        chomp($dicomFile);

        my $header = `gdcmdump $dicomFile`;

        my $protocolName = "";

        # For implicit transfer syntax, gdcm will print
        # (0000,0000) ?? (DA) [Value] where the DA in parentheses is the expected data type
        #
        # We match this with (?:\?\? \()?DA\)?
        if ($header =~ m/\s*\(0018,1030\) (?:\?\? \()?LO\)? \[(\w+)/) {
            $protocolName = $1;
        }
        else {
            die("Cannot read protocol name from dicom file $dicomFile");
        }

        if (exists($structuralProtocols{$protocolName})) {
            push(@structuralSeries, $seriesLabel);
        }
        else {
            print "Not defacing $protocolName\n";
        }
    }

    return @structuralSeries;

}

sub checkRequiredPrograms {

    my @dependencies = @_;

    foreach my $dep (@dependencies) {
        my $whichDep = `which $dep 2> /dev/null`;
        if (!$whichDep) {
            die("Cannot find required program $dep")
        }
    }

    return(0);

}
