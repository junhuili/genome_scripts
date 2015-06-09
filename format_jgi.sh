#!/bin/bash

# script to format JGI GFF and Fasta files to GBK and SMURF input
# Jon Palmer: palmer.jona@gmail.com

#run test if no files given, print usage
if [ -z "$1" ]; then
	echo "Run this script as follows:
	$0 <GFF file> <Fasta file> <Genome Name> <CPUS> <BlastDB>"
	exit
else
    #check to see if all programs are installed and in path
    command -v gsed >/dev/null 2>&1 || { echo "I require gsed but it's not installed.  Aborting." >&2; exit 1; }
    command -v gag.py >/dev/null 2>&1 || { echo "I require gag.py but it's not installed.  Aborting." >&2; exit 1; }
    command -v tbl2asn >/dev/null 2>&1 || { echo "I require tbl2asn but it's not installed.  Aborting." >&2; exit 1; }
    command -v gb2proteins.py >/dev/null 2>&1 || { echo "I require gb2proteins.py but it's not installed.  Aborting." >&2; exit 1; }
    command -v blastp >/dev/null 2>&1 || { echo "I require blastp but it's not installed.  Aborting." >&2; exit 1; }
    command -v gsort >/dev/null 2>&1 || { echo "I require gsort but it's not installed.  Aborting." >&2; exit 1; }
    command -v gawk >/dev/null 2>&1 || { echo "I require gawk but it's not installed.  Aborting." >&2; exit 1; }
    command -v gb2smurf.py >/dev/null 2>&1 || { echo "I require gb2smurf.py but it's not installed.  Aborting." >&2; exit 1; }
    
    #if CPUS not set, set it to max on system minus 1
    max_cores=$(sysctl -n hw.ncpu)
    num_cores=$(( max_cores - 1))
    if [ -z "$4" ]; then
        cpus=$num_cores
    else
        cpus=$4
    fi
    #if BlastDB not set, set it to swissprot by default
    if [ -z "$5" ]; then
        blast_db=swissprot
    else
        blast_db=$5
    fi
    echo "------------------------"
    #new check if blastDB is found on system
    if [ -f $BLASTDB/$blast_db.pal ]; then
        echo "Blast database $blast_db found, moving on."
    else
        echo "Blast database $blast_db not found, Aborting."
        exit
    fi
    #get current directory for writing results to
    dir=$PWD
    #make folder
    mkdir -p $3
    #first need to reformat GFF - alter some problematic regions
    gsed 's/jgi.p|//g' $1 | gsed 's/|/_/g' > $3/genome.gff
    #now reformat fasta headers to match GFF file
    cp $2 $3/genome.fasta
    #try running command line gag
    cd $dir/$3
    echo "------------------------"
    echo "Running GAG."
    echo "------------------------"
    gag.py fasta=genome.fasta gff=genome.gff
    cd $dir/$3/gag_output
    cp genome.fasta genome.fsa
    echo "------------------------"
    echo "Running tbl2asn."
    echo "------------------------"
    tbl2asn -p . -t $HOME/test.sbt -M n -Z discrep -a r10u -l paired-ends -j "[organism=$3]" -V b -c fx
    echo "------------------------"
    echo "Conversion to GBK was completed successfully, your file $3.gbk was created."
    gb2proteins.py genome.gbf $3.proteins.fasta
    echo "------------------------"
    echo "Now running Blastp of $5 to get minimal functional annotation."
    echo "------------------------"
    blastp -query $3.proteins.fasta -db $blast_db -max_target_seqs 1 -num_threads $cpus -outfmt "6 qseqid qlen sseqid slen length pident evalue stitle" -out $3.blast.tab
    #get best hit and format results
    gsort -k1,1 -k6,6g $3.blast.tab | gsort -u -k1,1 | gawk -F"\t" '{if($6 >= 50) print $1"\t""product""\t"$8;}' | gsed 's/RecName: Full=//g' | gsed 's/; AltName.*$//g' | gsed 's/ \[.*$//g' | gsed 's/; Short.*$//g' | gsed 's/; Flag.*$//g' | gsed 's/; Contains.*$//g' | gsed 's/; Includes.*$//g' | gsed 's/^gene_/mRNA_/g' > $3.annotation.txt
    echo "Blast complete, now formatting results to get annotation"
    echo "------------------------"
    echo "Running GAG."
    echo "------------------------"
    gag.py fasta=genome.fasta gff=genome.gff anno=$3.annotation.txt out=gag_product
    cd $dir/$3/gag_output/gag_product
    cp genome.fasta genome.fsa
    echo "------------------------"
    echo "Running tbl2asn."
    echo "------------------------"
    tbl2asn -p . -t $HOME/test.sbt -M n -Z discrep -a r10u -l paired-ends -j "[organism=$3]" -V b -c fx
    cp genome.gbf $dir/$3.gbk
    cd $dir
    gb2smurf.py $3.gbk -p $3.proteins.fasta -g $3.scaffolds.fasta -s $3.smurf.txt --jgi 
     echo "------------------------"
    echo "
    SMURF output is complete, script finished!
    
    Results:
        $3.gbk
        $3.proteins.fasta
        $3.scaffolds.fasta
        $3.smurf.txt
        
    Now you can submit $3.proteins.fasta and $3.smurf.txt to http://jcvi.org/smurf/upload.php
    
    And you can submit $3.gbk to AntiSmash (http://antismash.secondarymetabolites.org)
    
    "
     echo "------------------------"
fi