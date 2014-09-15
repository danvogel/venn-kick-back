#!perl

# HACK HACK HACK :-)

use strict;
use warnings;
use Carp;

use File::Basename qw(dirname basename);
use JSON::XS;

my $SCRIPT_DIR = dirname($0);
my $PROFILE_CACHE = $SCRIPT_DIR . '/profile/';
my $PROFILE_URL = 'https://www.kickstarter.com/profile/';

sub profile_cache_name
{
    my ($profile_id, undef) = @_;
    
    my $profile_escaped = $profile_id;
    $profile_escaped =~ s/\?/__/gixm;
    $profile_escaped =~ s/page=//gixm;

    return $PROFILE_CACHE . $profile_escaped;
}

sub download_profile 
{
    my ($profile_id, undef) = @_;
    my $cache_name = profile_cache_name($profile_id);

    if (-e $cache_name)
    {
	print STDERR qq{$profile_id: already have profile locally as $cache_name\n};
	return;
    }

    my @cmd = (
	q{curl },
	q{'}, $PROFILE_URL, $profile_id, q{'}, 
	q{ -o },
	$cache_name
	);

    my $cmd_str = join(q{}, @cmd);
    #print $cmd_str, qq{\n};
    print STDERR qq{$profile_id: Downloading profile...\n};
    system($cmd_str);
    return;
}

sub read_profile_meta
{
    my ($profile_content, undef) = @_;

    my %rtn = ();
    my @meta = grep { /kickstarter:/ixm } grep { /\<meta/ixm } @{$profile_content};
    push(@meta, grep { /og:description/ } @{$profile_content});

    foreach my $m (@meta)
    {
	my ($key, $val);
	if ($m =~ /property=\"(.*?)\"/gixm)
	{
	    $key = $1;
	}

	if ($m =~ /content=\"(.*?)\"/gixm)
	{
	    $val = $1;
	}
    
	$rtn{$key} = $val;
    }

    return \%rtn;
}

sub read_profile_content
{
    my ($profile_id, undef) = @_;
    my $profile_h;

    download_profile($profile_id);

    my $cache_name = profile_cache_name($profile_id);
    open($profile_h, q{<}, $cache_name) or
	croak(qq{Unable to open profile '$profile_id' as '$cache_name'});
    my @profile = <$profile_h>;
    close($profile_h) or
	croak(qq{Unable to open profile '$profile_id'});

    chomp(@profile);

    return \@profile;
}

sub extract_additional_pages
{
    my ($profile_content, undef) = @_;

    my %additional_pages = ();

    # Really crude at the moment
    foreach my $profile_line (grep { /\"pagination\"/ixm } @{$profile_content})
    {
	my @a_tags = split(q{<a }, $profile_line);

	foreach my $link (@a_tags)
	{
	    if ($link =~ /href=\"\/profile\/(\S+)\"/ixm)
	    {
		$additional_pages{$1} = 1;
	    }
	}
    }

    foreach my $add_p (sort keys %additional_pages)
    {
	print STDERR qq{Additional Page: $add_p\n};
    }

    return [ sort keys %additional_pages ];
}

sub extract_backed_projects
{
    my ($profile_content, undef) = @_;
    
    my %rtn = ();
    foreach my $project_line (grep { m/projects/mixm }
			      grep { /project_item/ } 
			      @{$profile_content})
    {
	if ($project_line =~ /href=\"\/projects\/(\S+)\"/ixm)
	{
	    $rtn{$1} = 1;
	} else {
	    carp(qq{Warning: no href in $project_line\n});
        }
    }
    return [sort keys %rtn];
}

sub repr_profile_meta
{
    my ($id, $meta, undef) = @_;
    
    my %meta_map = ();
    foreach my $k (sort keys %{$meta})
    {
	# Kickstarter meta names are like 'kickstarter:name' and 'og:description';
	# really more interested in not dealing with colons and the second part
	# seems more descriptive.
	my (undef, $primary) = split(q{:}, $k, 2);

	$meta_map{$primary} = $meta->{$k};
    }

    $meta_map{user} = $id;
    $meta_map{vennback} = q{profile_meta};

    return encode_json \%meta_map;
}

sub repr_project_backed
{
    my ($id, $proj, undef) = @_;
    return encode_json { project => $proj,
			 vennback => q{profile_back},
			 backer => $id };
}

sub read_profile
{
    my ($profile_id, undef) = @_;

    my $profile_content = read_profile_content($profile_id);

    my $meta = read_profile_meta($profile_content);
    print repr_profile_meta($profile_id, $meta), qq{\n};

    my $profile_paged = extract_additional_pages($profile_content);
    foreach my $profile_page (@{$profile_paged})
    {
	print STDERR join(q{, }, $profile_id, $profile_page), qq{\n};
    }

    foreach my $profile_page (@{$profile_paged})
    {
	my $profile_content_ext = read_profile_content($profile_page);
	push(@{$profile_content}, @{$profile_content_ext});
    }

    my @projects = @{extract_backed_projects($profile_content)};

    foreach my $proj (@projects)
    {
	print repr_project_backed($profile_id, $proj), qq{\n};
    }
    return;
}

sub main
{
    # TODO: Argument processing
    # FEATURE: cache-buster argument for read_profile

    if (!scalar @ARGV) {
	push(@ARGV, 'dmv');
    }

    foreach my $profile (@ARGV)
    {
	read_profile($profile);
    }
    return;
}

main();
