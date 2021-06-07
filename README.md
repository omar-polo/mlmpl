# mlmpl

mlmpl is a simple mailing list and newsletter manager script.  It's
meant to be used as mta script.

## Dependencies

 - p5-DBI
 - p5-DBD-SQLite
 - p5-Email-Simple

## How it works

`mlmpl` is made by two things:

 - `mda.pl`: this is the MDA (mail delivery agent).  Your mail server
   should call this script and provide three arguments: the receipt,
   the mailing list address and the sender address.
 - `mlmctl.pl`: it's used to create and manage mailing lists.

both will look for `/etc/mlmpl/config.pl` (or any other file pointed
by `$MLMPL_CONFIG`).

## Tutorial

1. make sure you have all the dependencies installed
2. fetch the code
```
git clone https://git.omarpolo.com/mlmpl
```
3. copy `config.pl` in `/etc/mlmpl/config.pl` and customize the fields
4. initialize the database

```
sqlite3 /path/to/db.sqlite < schema.sql
```

5. create a mailing list/news letter

```
./mlmctl.pl add news@example.com	\
	name='Example news letter'		\
	public=false					\
	archive=true					\
	moderated=true
```

6. add a moderator

```
./mlmctl.pl moderator news@example.com your@email.addre.ss
```

7. point your mail server to `mda.pl`.


## using mlmpl with OpenSMTPD

To use it with OpenSMTPD you need two tables.  Other setups are
possible, but this is what I reccomend:

 - the list of addresses:

```
# /etc/mail/news-addresses
news@example.com
owner-news@example.com
subscribe-news@example.com
unsubscribe-news@example.com
help-news@example.com
```

 - an alias table so OpenSMTPD can recognise the addresses:

```
# /etc/mail/news-aliases
news           localuser
owner          localuser
subscribe      localuser
unsubscribe    localuser
help           localuser
```

Then you can hook everything together with:

```
table news         file:/etc/mail/news-addresses
table news-aliases file:/etc/mail/news-aliases

action "newsletter" \
	mda "/usr/bin/perl /path/mda.pl %{rcpt:lowercase|strip} news@example.com %{sender:lowercase|strip}" \
	user "localuser" \
	alias <news-aliases>

match from any for rcpt-to <news> action "newsletter"

# "! rcpt-to" so mails for the mailing list don't get matched
match from any for domain <domains> ! rcpt-to <news> action "local_mail"
```
