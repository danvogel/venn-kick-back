#!perl

use strict;
use warnings;
use Carp;

use File::Basename qw(dirname basename);
use JSON::XS;


my $SCRIPT_DIR = dirname($0);
my $INPUT_DIR = $SCRIPT_DIR . '/input/';
my $PROJECT_SCRIPT = qq{perl project_into_recs.pl -q};

sub evaluate_project_json
{
    my ($proj_json, undef) = @_;

    my $meta;
    my @backer = ();

    foreach my $j_line (@{$proj_json})
    {
	my $d_line = decode_json $j_line;
	if (!defined $d_line->{vennback})
	{
	    next;
	}
	else
	{
	    if ($d_line->{vennback} eq q{project_back})
	    {
		push(@backer, $d_line->{backer});
	    }
	    elsif ($d_line->{vennback} eq q{project_meta})
	    {
		$meta = $d_line;
	    }
	}
    }
    
    return {
	backers => \@backer,
	meta => $meta,
	id => $meta->{id}
    };
}

sub overlap
{
    my ($a, $b, undef) = @_;
    my %a_list = ();
    my %b_list = ();

    my $a_only = 0;
    my $b_only = 0;
    my $both = 0;

    foreach my $c_a (@{$a})
    {
	$a_list{$c_a} = 1;
    }

    foreach my $c_b (@{$b})
    {
	$b_list{$c_b} = 1;
    }

    $a_only = scalar keys %a_list;
    $b_only = scalar keys %b_list;

    foreach my $c_b (keys %b_list)
    {
	if (defined $a_list{$c_b}) {
	    ++$both;
	    --$a_only;
	    --$b_only;
	}
    }
    return { 
	'a_only' => $a_only, 
	'b_only' => $b_only,
	'both'   => $both
    };
}

sub report_on_backers
{
    my ($meta, $backers, undef) = @_;

    foreach my $i_id (sort keys %{$backers})
    {
	print encode_json $meta->{$i_id}, qq{\n};
	my @all_other_backers = ();
	print qq{\tTotal project backers: }, scalar @{$backers->{$i_id}}, qq{\n};
	foreach my $j_id (sort keys %{$backers})
	{
	    ($i_id eq $j_id) and next;
	    my $over = overlap($backers->{$i_id}, $backers->{$j_id});
	    print qq{\tShares backers with $j_id: $over->{both}\n};
	    push(@all_other_backers, @{$backers->{$j_id}});
	}
	my $over = overlap($backers->{$i_id}, \@all_other_backers);
	print qq{\tShares backers with all candidate projects: $over->{both}\n};
    }
    return;
}

sub process_project_list
{
    my ($project_list, undef) = @_;
    my %project_backers = ();
    my %project_meta = ();

    foreach my $project (@{$project_list})
    {
	$project =~ s/^https\:\/\///ixgm;
	my $cmd = qq{$PROJECT_SCRIPT $project};
	print STDERR qq{$cmd\n};

	open(my $prj_f, q{-|}, $cmd) or croak(qq{Unable to open-exec: '$cmd'});
	my @proj_json = <$prj_f>;
	close($prj_f) or croak(qq{Unable to close-exec: '$cmd'});
	chomp(@proj_json);

	my $eval = evaluate_project_json(\@proj_json);

	$project_meta{$eval->{id}} = $eval->{meta};
	$project_backers{$eval->{id}} = $eval->{backers};
    }

    report_on_backers(\%project_meta, \%project_backers);
    return;
}

sub main
{
    foreach my $input_file (@ARGV)
    {
	open(my $in_f, q{<}, $input_file) or croak(qq{Cannot open '$input_file'});
	my @project_list = <$in_f>;
	close($in_f) or croak(qq{Cannot close '$input_file'});

	chomp(@project_list);
	process_project_list(\@project_list);
    }

    return;
}

main();
