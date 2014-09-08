#!perl

# HACK HACK HACK :-)

use strict;
use warnings;
use Carp;

use File::Basename qw(dirname basename);

my $TIME_BETWEEN_PAGE_REQUESTS = 3; # time, in s, between additional page loads

my $SCRIPT_DIR = dirname($0);
my $PROJECT_CACHE = $SCRIPT_DIR . q{/projects/};
my $BACKER_PAGE = q{/backers};
my $PROJECT_URL = q{https://www.kickstarter.com/projects/};

sub project_cache_name
{
    my ($project_id, $project_post, undef) = @_;

    my $project_escaped = $project_id;
    if ($project_post)
    {
	$project_escaped .= $project_post;
    }
    $project_escaped =~ s/backers//gixm;
    $project_escaped =~ s/\?/__/gixm;
    $project_escaped =~ s/page=//gixm;
    $project_escaped =~ s/\//\./gixm;

    return $PROJECT_CACHE . $project_escaped;
}

sub download_project
{
    my ($project_id, $project_post, undef) = @_;
    my $cache_name = project_cache_name($project_id, $project_post);

    if (!$project_post)
    {
	$project_post = $BACKER_PAGE;
    }


    if (-e $cache_name)
    {
	print STDERR qq{$project_id: already have project locally as $cache_name\n};
	return;
    }

    my @cmd = (
	q{curl },
	q{'}, $PROJECT_URL, $project_id, $project_post, q{'}, 
	q{ -o },
	$cache_name
	);

    my $cmd_str = join(q{}, @cmd);
    #print $cmd_str, qq{\n};
    print STDERR qq{$project_id: Downloading project...\n};
    system($cmd_str);
    sleep($TIME_BETWEEN_PAGE_REQUESTS);
    return;
}

sub read_project_backers
{
    my ($profile_content, undef) = @_;

    my %backers = ();

    for (my $i = 0; $i < scalar @{$profile_content}; ++$i)
    {
	my $line = $profile_content->[$i];

	if ($line !~ /NS\_backers\_\_backing\_row/)
	{
	    next;
	}

	++$i;
	$line = $profile_content->[$i];
	if ($line =~ /\"\/profile\/(\w+)\"/ixm)
	{
	    $backers{$1} = 1;
	}
    }
    
    return [ sort keys %backers ];
}

sub read_project_meta
{
    my ($profile_content, undef) = @_;

    my %rtn = ();
    my @meta = grep { /kickstarter:/ixm } grep { /\<meta/ixm } @{$profile_content};
    push(@meta, grep { /twitter:text/ixm } @{$profile_content});

    foreach my $m (@meta)
    {
	my ($key, $val);
	if ($m =~ /property=\"(.*?)\"/gixm)
	{
	    my @a = split(q{:}, $1);
	    $key = pop @a;
	}

	if ($m =~ /content=\"(.*?)\"/gixm)
	{
	    $val = $1;
	}
    
	if ($key eq q{backers})
	{
	    $val =~ s/,//gixm;
	}

	if ($key eq q{pledged})
	{
	    $val =~ s/\D+//gixm;
	}

	$rtn{$key} = $val;
    }

    foreach my $main_content_div (grep { /id\=\"main\_content\"/ixm } @{$profile_content})
    {
	if ($main_content_div =~ /class=\"(.+)\" /ixm)
	{
	    foreach my $class (split(/\s+/ixm, $1))
	    {
		if ($class =~ /^Project-ended-(.*)/ixm)
		{
		    $rtn{project_ended} = $1;
		}
		
		if ($class =~ /^Project-state-(.*)/ixm)
		{
		    $rtn{project_state} = $1;
		}
	    }
	}
    }

    return \%rtn;
}

sub extract_additional_pages
{
    my ($profile_content, undef) = @_;

    my @additional_pages = ();

    my $max_page = 1;

    foreach my $profile_line (grep { /\"pagination\"/ixm } @{$profile_content})
    {
	my @a_tags = split(q{<a }, $profile_line);

	foreach my $link (@a_tags)
	{
	    if ($link =~ /\/backers\?page=(\d+)\"/ixm && ($1 > $max_page))
	    {
		$max_page = $1;
	    }
	}
    }
   
    if (1 < $max_page)
    {
	for (my $i = 2; $i <= $max_page; ++$i)
	{
	    push(@additional_pages, q{/backers?page=} . $i);
	}
    }
    return \@additional_pages;
}

sub read_project_content
{
    my ($project_id, $project_post, undef) = @_;
    my $project_h;

    download_project($project_id, $project_post);

    my $cache_name = project_cache_name($project_id, $project_post);
    open($project_h, q{<}, $cache_name) or
	croak(qq{Unable to open project '$project_id' as '$cache_name'});
    my @project = <$project_h>;
    close($project_h) or
	croak(qq{Unable to open project '$project_id'});

    chomp(@project);

    return \@project;
}

sub repr_project_meta
{
    my ($project_map, $meta, undef) = @_;
    
    $meta->{id}       = $project_map->{p_id};
    $meta->{user}     = $project_map->{p_maker};
    $meta->{title}    = $project_map->{p_title};
    $meta->{vennback} = q{project_meta};

    my $s = '{ ';
    $s .= join(q{, }, map { qq{"$_": "$meta->{$_}"} } sort keys %{$meta});
    $s .= ' }';
    return $s;
}

sub repr_project_backers
{
    my ($project_map, $backers, undef) = @_;

    my @s_list = ();
    foreach my $back (@{$backers})
    {
	my $s = '{ ' . qq{'id': '$project_map->{p_id}', 'vennback': 'project_back', 'backer': '$back'} . ' }';
	push(@s_list, $s);
	
    }
    return join(qq{\n}, @s_list);
}

sub read_project
{
    my ($project_map, undef) = @_;

    my $project_content = read_project_content($project_map->{p_id}, q{});

    my $meta = read_project_meta($project_content);
    print repr_project_meta($project_map, $meta), qq{\n};

    my $project_paged = extract_additional_pages($project_content);
    #foreach my $project_page (@{$project_paged})
    #{
    #print STDERR join(q{, }, $project_map->{p_id}, $project_page), qq{\n};
    #}
    foreach my $project_page (@{$project_paged})
    {
	my $project_content_ext = read_project_content($project_map->{p_id}, $project_page);
	push(@${project_content}, @{$project_content_ext});
    }

    my $backers = read_project_backers($project_content);
    print repr_project_backers($project_map, $backers), qq{\n};

    return;
}

sub split_project
{
    my ($project_id, undef) = @_;
    # strip beginning parts if it's a URL
    $project_id =~ s/^.*\/projects\///gixm;

    # strip ending parts if it's a URL
    $project_id =~ s/\?.*$//gixm;

    my ($project_maker, $project_title) = split(q{/}, $project_id);
    return { 
	p_maker => $project_maker,
	p_title => $project_title,
	p_id    => $project_id
    };
}

sub main
{
    # TODO: Argument processing
    
    if (!scalar @ARGV)
    {
	push(@ARGV, 'yonder/dino-pet-a-living-bioluminescent-night-light-pet');
    }

    if (!-d $PROJECT_CACHE)
    {
	mkdir $PROJECT_CACHE;
    }

    foreach my $project_raw (@ARGV)
    {
	my $project_map = split_project($project_raw);
	if ($project_map && scalar keys $project_map)
	{
	    read_project($project_map);
	}
    }
    return;
}

main();
