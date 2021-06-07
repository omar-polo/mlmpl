#!/usr/bin/env perl

use strict;
use v5.10;
use warnings;

use DBI;
use Net::SMTP;
use Email::Simple;
use Time::HiRes qw(gettimeofday);
use File::Path qw(make_path);
use Sys::Hostname;
use Data::Dumper;

our $archive_dir;
our $db_file = "db.sqlite";
our $mail_template_dir;

our $smtpserver = "localhost";
our $smtpport = 25;

do ($ENV{'MLMPL_CONFIG'} or '/etc/mlmpl/config.pl') or die 'cannot open config!';

sub tobool {
	$_[0] =~ 'true';
}

sub r {
	my ($file, %opt) = @_;
	open(my $f, "<", $mail_template_dir .'/'. $file);
	my $r = join '', <$f>;
	close($f);
	$r =~ s/\$owner/$opt{owner}/g;
	$r =~ s/\$sender/$opt{sender}/g;
	$r =~ s/\$ml/$opt{name}/g;
	$r =~ s/\$subaddr/$opt{subscribe}/g;
	$r =~ s/\$unsubaddr/$opt{unsubscribe}/g;
	$r =~ s/\$helpaddr/$opt{helpaddr}/g;
	return $r;
}

# make dir if needed
sub mkdirin {
	if (! -d $_[0]) {
		make_path($_[0]);
	}
}

# from [to] mail_str
sub send_email {
	my ($from, $tos, $mail) = @_;

	my $smtp = Net::SMTP->new($smtpserver, Port => $smtpport, Timeout=>10, Debug=>0);

	# Optionally, add authentication here. A simple example with
	# username & password:
	#
	# $smtp->auth($smtpuser, $smtppassword);
	#
	# see https://metacpan.org/pod/Net::SMTP for a full
	# description of Net::SMTP method.

	$smtp->mail($from);
	foreach my $s (@$tos) {
		$smtp->to("$s");
	}
	$smtp->data();
	$smtp->datasend($mail);
	$smtp->dataend();
	$smtp->close();
	return;
}

if (!@ARGV) {
	die('no data given');
}

my $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", "", "", {AutoCommit=>1, RaiseError=>0, PrintError=>1});

# mda.pl <rcpt> <ml> <sender>
my $action = shift @ARGV;
my $ml     = shift @ARGV;
my $sender = shift @ARGV;

if (!$action || !$ml || !$sender) {
	die('missing action, ml and/or sender');
}

my $q = $dbh->prepare('select name, public, moderated, archive, addr, owner, subscribe, unsubscribe, help from ml where addr = ?');
$q->execute($ml);
my @r = $q->fetchrow_array();

my %list = (
	name => $r[0],
	#public => tobool($r[1]),
	#moderated => tobool($r[2]),
	#archive => tobool($r[3]),
	addr => $r[4],
	owner => $r[5],
	subscribe => $r[6],
	unsubscribe => $r[7],
	help => $r[8],

	# it's handy to have this here, so we can pass %list to r
	sender => $sender
);
$list{public} = tobool $r[1];
$list{moderated} = tobool $r[2];
$list{archive} = tobool $r[3];

if ($action eq $list{subscribe}) {
	my $q = $dbh->prepare('insert into subs(ml, guy) values (?, ?)');

	# if it fails, it means that the user is already subscribed,
	# or the ml doesn't exists. soft-ignore this request
	$q->execute($ml, $sender) or exit(0);

	my $mail = r('subscribed', %list);
	send_email($list{'addr'}, [$sender], $mail);
} elsif ($action eq $list{unsubscribe}) {
	# get the subs date
	my $q = $dbh->prepare('select sub_date from subs where ml = ? and guy = ?');
	$q->execute($ml, $sender);
	my @res = $q->fetchrow_array();

	# the user may not be subscribed, the list may not exists and
	# so on... Kindly ignore this request
	if (@res == 0) {
		exit 0
	}

	my $was = $res[0];

	# delete from subs
	$q = $dbh->prepare('delete from subs where ml = ? and guy = ?');
	$q->execute($ml, $sender);

	# record the unsubscription
	$q = $dbh->prepare('insert into unsubscribed(ml, guy, was) values (?,?,?)');
	$q->execute($ml, $sender, $was);

	my $mail = r('unsubscribed', %list);
	send_email($list{'addr'}, [$sender], $mail);
} elsif ($action eq $list{help}) {
	my $mail = r('help', %list);
	send_email($list{'addr'}, [$sender], $mail);
} else {
	my $mail = Email::Simple->new(join "", <STDIN>);

	# check if the list is moderated and the $sender is a moderator
	if ($list{'moderated'}) {
		my $q = $dbh->prepare('select count(*) from moderators where ml = ? and guy = ?');
		$q->execute($ml, $sender);
		my $r = $q->fetchall_arrayref;
		if ($r->[0][0] == 0) {
			#send_email($list{owner}, [$list{owner}], $mail->as_string);
			send_email($list{owner}, ['postmaster@list.example.com'], $mail->as_string);
			exit 0;
		}
	}

	my $subject = $mail->header("Subject");
	my $body = $mail->body;

	my @l = $mail->header_obj->header_pairs;
	my @headers;
	while (@l) {
		my $h = shift @l;
		my $v = shift @l;
		if ($h =~ m/^Content-.*/ or $h =~ m/^MIME-.*/) {
			push(@headers, $h);
			push(@headers, $v);
		}
	}

	my $name = $list{'name'};
	my $owner = $list{'owner'};
	my $subscribe = $list{'subscribe'};
	my $unsubscribe = $list{'unsubscribe'};
	my $help = $list{'help'};

	# add some well-known headers
	push(@headers, "List-Help");		push(@headers, "<mailto:$help>");
	push(@headers, "List-Id");		push(@headers, "<$ml>");
	push(@headers, "List-Owner");		push(@headers, "<mailto:$owner>");
	push(@headers, "List-Post");		push(@headers, "<mailto:$ml>");
	push(@headers, "List-Subscribe");	push(@headers, "<mailto:$subscribe>");
	push(@headers, "List-Unsubscribe");	push(@headers, "<mailto:$unsubscribe>");
	push(@headers, "Sender");		push(@headers, "$owner");
	push(@headers, "X-Complaints-To");	push(@headers, "$owner");

	push(@headers, "To");			push(@headers, "$ml");

	if ($list{'public'}) {
		push(@headers, "From");		push(@headers, $mail->header('From'));
	} else {
		push(@headers, "From");		push(@headers, "\"$name\" <$ml>");
	}

	if ($subject) {
		push(@headers, "Subject");	push(@headers, $subject);
	}

	# NOTE: it seems that the Date header is automatically
	# added by the as_string method on Email::Simple!

	my $newmail = Email::Simple->create(
		header => [ @headers ],
		body   => $body,
	);
	my $newmail_s = $newmail->as_string;

	# write the archive
	if ($list{'archive'}) {
		my $tmp = $archive_dir .'/'. $ml .'/tmp'; mkdirin $tmp;
		my $cur = $archive_dir .'/'. $ml .'/cur'; mkdirin $cur;

		my @syms = ( 'a'..'z', 'A'..'Z', '0'..'9' );
		my $random = join '', map $syms[rand(@syms)], 1..32;
		my ($seconds, $microseconds) = gettimeofday;
		my $file = "${seconds}.M${microseconds}P${$}R${random}.". hostname;

		# write email in tmp
		open (my $f, ">", $tmp .'/'. $file);
		print $f $newmail_s;
		close($f);

		# link from tmp to cur and delete from tmp
		link $tmp.'/'.$file, $cur.'/'.$file;
		unlink $tmp.'/'.$file;
	}

	# get the subs
	my $q = $dbh->prepare('select guy from subs where ml = ?');
	$q->execute($ml);
	my @subs = $q->fetchall_arrayref;
	# flatten it a bit
	@subs = map {@$_} @subs;
	@subs = map {@$_} @subs;

	my @chunks;
	push @chunks, [ splice @subs, 0, 50 ] while @subs;

	# send email by chunks
	foreach (@chunks) {
		send_email($list{'owner'}, $_, $newmail_s);
		sleep 10;
	}
}

undef $dbh;
