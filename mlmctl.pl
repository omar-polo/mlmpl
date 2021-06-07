#!/usr/bin/env perl

use strict;
use warnings;
use v5.10;

use DBI;

our $db_file;

do ($ENV{'MLMPL_CONFIG'} or '/etc/mlmpl/config.pl') or die 'cannot open config!';

sub usage {
	print "Usage: action ...\n";
	print " Where action can be:\n\n";

	print " - help\n";
	print "   Prints this message.\n\n";

	print " - list [ml] [mod]\n";
	print "   List all mailing lists, all subscribers the given ml or all the mod\n";
	print "   in the given ml.\n\n";

	print " - add ml [options]\n";
	print "   Add a new mailing list. The options are `name=<name>` (default ''),\n";
	print "   `publi=bool` (default true), `moderated=bool` (default false),\n";
	print "   `archive=bool` (default true).\n\n";

	print " - edit ml [options]\n";
	print "   Like add, but used to edit the option of the given mailing\n";
	print "   list. Will also print a nice BEFORE/AFTER table for comparisons.\n\n";

	print " - subscribe ml email\n";
	print "   Manually add the given email address to the subscribers of the\n";
	print "   mailing list ml.\n\n";

	print " - moderator\n";
	print "   Like subscribe but for moderators.\n\n";

	print " - del [subaction]\n";
	print "   where subaction is one of:\n";
	print "   - mod ml email\n";
	print "   - sub ml email\n";
	print "   - list ml\n";
}

sub tobool {
	if ($_[0] =~ /(on|true|1)$/) {
		return "true";
	}
	return "false";
}

sub checkmail {
	if ($_[0] !~ /@/) {
		die("'" . $_[0] . "' doesn't seem to be an email address.");
	}
}

# ex: parseopt {}, @ARGV
sub parseopt {
	my (%opt, @list) = @_;

	foreach (@ARGV) {
		if ($_ =~ /^name=/) {
			($opt{'name'} = $_) =~ s/name=//;
		} elsif ($_ =~ /^public=/) {
			$opt{'public'} = tobool $_;
		} elsif ($_ =~ /^moderated=/) {
			$opt{'moderated'} = tobool $_;
		} elsif ($_ =~ /^archive=/) {
			$opt{'archive'} = tobool $_;
		} elsif ($_ =~ /^owner=/) {
			($opt{'owner'} = $_) =~ s/owner=//;
		} elsif ($_ =~ /^subscribe=/) {
			($opt{'subscribe'} = $_) =~ s/subscribe=//;
		} elsif ($_ =~ /^unsubscribe=/) {
			($opt{'unsubscribe'} = $_) =~ s/unsubscribe=//;
		} elsif ($_ =~ /^help=/) {
			($opt{'help'} = $_) =~ s/help=//;
		} else {
			die("Unrecognized option $_");
		}
	}

	return %opt;
}

if (!@ARGV) {
	usage; exit 1;
}

my $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", "", "", {AutoCommit=>1, RaiseError=>1, PrintError=>1});

my $action = shift @ARGV;

if ($action eq "help") {
	usage; exit 0;
}

if ($action eq "list") {
	my $ml = shift @ARGV;
	if ($ml) {
		my $a = shift @ARGV;
		if ($a =~ m/mod/) {
			my $q = $dbh->prepare('select guy from moderators where ml = ?');
			$q->execute($ml);
			while (my @r = $q->fetchrow_array()) {
				say $r[0];
			}

			exit 0;
		}

		my $q = $dbh->prepare('select guy from subs where ml = ?');
		$q->execute($ml);
		while (my @r = $q->fetchrow_array()) {
			say $r[0];
		}
	} else {
		my $q = $dbh->prepare('select addr from ml');
		$q->execute();
		while (my @r = $q->fetchrow_array()) {
			say $r[0];
		}
	}

	exit 0;
}

if ($action eq "add") {
	my $ml = shift @ARGV;
	checkmail $ml;

	my %opt = (
		name		=> "",
		public		=> 'true',
		moderated	=> 'false',
		archive		=> 'true',
		owner		=> "owner-". $ml,
		subscribe	=> "subscribe-". $ml,
		unsubscribe	=> "unsubscribe-". $ml,
		help		=> "help-". $ml
	    );

	%opt = parseopt %opt, @ARGV;

	my $q = $dbh->prepare('insert into ml(addr, name, public, moderated, archive, owner, subscribe, unsubscribe, help) values (?, ?, ?, ?, ?, ?, ?, ?, ?)')
	    or die("cannot prepare statement: $!");
	$q->execute($ml, $opt{'name'}, $opt{'public'}, $opt{'moderated'}, $opt{'archive'}, $opt{'owner'}, $opt{'subscribe'}, $opt{'unsubscribe'}, $opt{'help'})
	    or die("cannot add list: $!");

	print "Added ml $ml with the following option:\n";
	print "- name:        ". $opt{name} ."\n";
	print "- public:      ". $opt{public} ."\n";
	print "- moderated:   ". $opt{moderated} ."\n";
	print "- archive:     ". $opt{archive} ."\n";
	print "- owner:       ". $opt{owner} ."\n";
	print "- subscribe:   ". $opt{subscribe} ."\n";
	print "- unsubscribe: ". $opt{unsubscribe} ."\n";
	print "- help:        ". $opt{help} ."\n";

	exit 0;
}

if ($action eq "edit") {
	my $ml = shift @ARGV;
	checkmail $ml;
	my $q = $dbh->prepare('select addr, name, public, moderated, archive, owner, subscribe, unsubscribe, help from ml where addr = ?');
	$q->execute($ml);
	my @r = $q->fetchrow_array();

	my %opt = (
		addr => $r[0],
		name => $r[1],
		public => $r[2],
		moderated => $r[3],
		archive => $r[4],
		owner => $r[5],
		subscribe => $r[6],
		unsubscribe => $r[7],
		help => $r[8]
	    );

	print "\taddr\t\tname\tpublic\tmod\tarchive\towner\t\t\tsub\t\t\tunsub\t\t\t\thelp\n";
	print "BEFORE:\t". $opt{'addr'} ."\t". $opt{'name'} ."\t". $opt{'public'} ."\t". $opt{'moderated'} ."\t". $opt{'archive'} ."\t". $opt{'owner'} ."\t". $opt{'subscribe'} ."\t". $opt{'unsubscribe'} ."\t". $opt{'help'} ."\n";

	%opt = parseopt %opt, @ARGV;

	print "AFTER:\t". $opt{'addr'} ."\t". $opt{'name'} ."\t". $opt{'public'} ."\t". $opt{'moderated'} ."\t". $opt{'archive'} ."\t". $opt{'owner'} ."\t". $opt{'subscribe'} ."\t". $opt{'unsubscribe'} ."\t". $opt{'help'} ."\n";
	$q = $dbh->prepare('update ml set addr = ?,  name = ?, public = ?, moderated = ?, archive = ?, owner = ?, subscribe = ?, unsubscribe = ?, help = ? where addr = ?');
	$q->execute($opt{'addr'}, $opt{'name'}, $opt{'public'}, $opt{'moderated'}, $opt{'archive'}, $opt{'owner'}, $opt{'subscribe'}, $opt{'unsubscribe'}, $opt{'help'}, $ml);
	print "OK!\n";
}

if ($action eq "subscribe") {
	my $ml = shift @ARGV;
	my $guy = shift @ARGV;
	if ($guy) {
		checkmail $guy;

		my $q = $dbh->prepare('insert into subs(ml, guy) values (?, ?)');
		$q->execute($ml, $guy) or die("can't subscribe $guy: $!");
		print "OK!\n";

		exit 0;
	}

	die('invalid syntax');
}

if ($action eq "moderator") {
	my $ml = shift @ARGV;
	if ($ml) {
		my $guy = shift @ARGV;

		checkmail $guy;

		my $q = $dbh->prepare('insert into moderators(ml, guy) values (?, ?)');
		$q->execute($ml, $guy) or die("can't add moderator $guy: $!");
		print "OK!\n";

		exit 0;
	}

	die("invalid syntax");
}

if ($action eq 'del') {
	my $subaction = shift @ARGV;
	my $ml = shift @ARGV;
	checkmail $ml;

	if ($subaction =~ m/^mod/) {
		my $guy = shift @ARGV;
		checkmail $guy;
		my $q = $dbh->prepare('delete from moderators where guy = ? and ml = ?');
		$q->execute($guy, $ml);
		print "OK!\n";
	} elsif ($subaction =~ m/^sub/) {
		my $guy = shift @ARGV;
		checkmail $guy;
		my $q = $dbh->prepare('delete from subs where guy = ? and ml = ?');
		$q->execute($guy, $ml);
		print "OK!\n";
	} elsif ($subaction =~ m/^list/) {
		my $q = $dbh->prepare('delete from ml where addr = ?');
		$q->execute($ml);
		print "OK!\n";
	} else {
		print STDERR "Invalid syntax.\n";
		exit 1;
	}
}
