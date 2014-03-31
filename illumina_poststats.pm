#!/usr/bin/perl -w

##################################################################################################################################################
###This script is designed to run picard metrics per sample and create a PDF summary using the ..... tool generated by R.F. Ernst
###
###
###Author: S.W.Boymans
###Latest change: Created skeleton
###
###TODO: A lot
##################################################################################################################################################

package illumina_poststats;

use strict;
use POSIX qw(tmpnam);
use FindBin;

sub runPostStats {
    my $configuration = shift;
    my %opt = %{readConfiguration($configuration)};
    my $javaMem = $opt{POSTSTATS_THREADS} * $opt{POSTSTATS_MEM};
    my $picard = "java -Xmx".$javaMem."G -jar $opt{PICARD_PATH}";
    my @runningJobs; #internal job array
    
    ### Run Picard for each sample
    foreach my $sample (@{$opt{SAMPLES}}){
	my $jobID;
	my $bam = $opt{OUTPUT_DIR}."/".$sample."/mapping/".$sample."_dedup.bam";
	my $picardOut = $opt{OUTPUT_DIR}."/".$sample."/QCStats/";
	my $command;
	
	### Multiple metrics
	unless (-e $picardOut.$sample."_MultipleMetrics.txt.alignment_summary_metrics" && -e $picardOut.$sample."_MultipleMetrics.txt.insert_size_metrics" && -e $picardOut.$sample."_MultipleMetrics.txt.quality_by_cycle_metrics" && -e $picardOut.$sample."_MultipleMetrics.txt.quality_distribution_metrics"){
	    $command = $picard."/CollectMultipleMetrics.jar R=$opt{GENOME} ASSUME_SORTED=TRUE OUTPUT=".$picardOut.$sample."_MultipleMetrics.txt INPUT=$bam PROGRAM=CollectAlignmentSummaryMetrics PROGRAM=CollectInsertSizeMetrics PROGRAM=QualityScoreDistribution PROGRAM=QualityScoreDistribution\n";
	    $jobID = bashAndSubmit($command,$sample,\%opt);
	    push(@runningJobs, $jobID);
	}
	
	### Library Complexity
	unless (-e $picardOut.$sample."_LibComplexity.txt"){
	    $command = $picard."/EstimateLibraryComplexity.jar OUTPUT=".$picardOut.$sample."_LibComplexity.txt INPUT=$bam";
	    $jobID = bashAndSubmit($command,$sample,\%opt);
	    push(@runningJobs, $jobID);
	}

	### Calculate HSMetrics -> only if target/bait file are present.
	if ( ($opt{POSTSTATS_TARGETS}) && ($opt{POSTSTATS_BAITS}) ) {
	    unless (-e $picardOut.$sample."_HSMetrics.txt"){
		$command = $picard."/CalculateHsMetrics.jar R=$opt{GENOME} OUTPUT=".$picardOut.$sample."_HSMetrics.txt INPUT=$bam BAIT_INTERVALS=$opt{POSTSTATS_BAITS} TARGET_INTERVALS=$opt{POSTSTATS_TARGETS} METRIC_ACCUMULATION_LEVEL=SAMPLE";
		$jobID = bashAndSubmit($command,$sample,\%opt);
		push(@runningJobs, $jobID);
	    }
	}
    }
    ### Run plotilluminametrics
    if(! -e "$opt{OUTPUT_DIR}/logs/PostStats.done"){
	my $command = "perl $FindBin::Bin/modules/plotIlluminaMetrics/plotIlluminaMetrics.pl ".join(" ",@{$opt{SAMPLES}});
    
	my $jobID = get_job_id();
	my $bashFile = $opt{OUTPUT_DIR}."/jobs/PICARD_".$jobID.".sh";
	my $logDir = $opt{OUTPUT_DIR}."/logs";
        
	open OUT, ">$bashFile" or die "cannot open file $bashFile\n";
	print OUT "#!/bin/bash\n\n";
	print OUT "cd $opt{OUTPUT_DIR}\n";
	print OUT "$command\n";
	print OUT "mv *HSMetric_summary* QCStats/ \n";
	print OUT "mv *picardMetrics* QCStats/ \n";
	print OUT "mv figure/ QCStats/ \n\n";
	print OUT "if [ -f QCStats/*.picardMetrics.pdf -a -f QCStats/*.picardMetrics.html ]\nthen\n";
	print OUT "\ttouch logs/PostStats.done \n";
	print OUT "fi\n";

	if (@runningJobs){
	    system "qsub -q $opt{POSTSTATS_QUEUE} -pe threaded $opt{POSTSTATS_THREADS} -o $logDir -e $logDir -N PICARD_$jobID -hold_jid ".join(",",@runningJobs)." $bashFile";
	} else {
	    system "qsub -q $opt{POSTSTATS_QUEUE} -pe threaded $opt{POSTSTATS_THREADS} -o $logDir -e $logDir -N PICARD_$jobID $bashFile";
	}
    }
}

sub readConfiguration{
    my $configuration = shift;
    my %opt;

    foreach my $key (keys %{$configuration}){
	$opt{$key} = $configuration->{$key};
    }

    if(! $opt{PICARD_PATH}){ die "ERROR: No PICARD_PATH found in .conf file\n" }
    if(! $opt{POSTSTATS_THREADS}){ die "ERROR: No POSTSTATS_THREADS found in .conf file\n" }
    if(! $opt{POSTSTATS_MEM}){ die "ERROR: No POSTSTATS_MEM found in .conf file\n" }
    if(! $opt{POSTSTATS_QUEUE}){ die "ERROR: No POSTSTATS_THREADS found in .conf file\n" }
    if(! $opt{GENOME}){ die "ERROR: No GENOME found in .conf file\n" }
    if(! $opt{OUTPUT_DIR}){ die "ERROR: No OUTPUT_DIR found in .conf file\n" }
    return \%opt;
}


############
sub get_job_id {
   my $id = tmpnam(); 
      $id=~s/\/tmp\/file//;
   return $id;
}

sub bashAndSubmit {
    my $command = shift;
    my $sample = shift;
    my %opt = %{shift()};
    
    my $jobID = get_job_id();
    my $bashFile = $opt{OUTPUT_DIR}."/".$sample."/jobs/PICARD_".$sample."_".$jobID.".sh";
    my $logDir = $opt{OUTPUT_DIR}."/".$sample."/logs";
    
    open OUT, ">$bashFile" or die "cannot open file $bashFile\n";
    print OUT "#!/bin/bash\n\n";
    print OUT "cd $opt{OUTPUT_DIR}\n";
    print OUT "$command\n";
    
    if ( $opt{RUNNING_JOBS}->{$sample} ){
	system "qsub -q $opt{POSTSTATS_QUEUE} -pe threaded $opt{POSTSTATS_THREADS} -o $logDir -e $logDir -N PICARD_$jobID -hold_jid ".join(",",@{$opt{RUNNING_JOBS}->{$sample} })." $bashFile";
    } else {
	system "qsub -q $opt{POSTSTATS_QUEUE} -pe threaded $opt{POSTSTATS_THREADS} -o $logDir -e $logDir -N PICARD_$jobID $bashFile";
    }
    return "PICARD_$jobID";
}

############ 

1;