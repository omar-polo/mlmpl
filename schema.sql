-----------------------------
-- >> Table definitions << --
-----------------------------

create table ml (
	addr		text	primary key,
	name		text,
	public		boolean	default true,
	moderated	boolean	default true,
	archive		boolean	default true,
	owner		text,
	subscribe	text,
	unsubscribe	text,
	help		text
	);

create table subs (
	ml		text	not null references ml(addr) on delete cascade on update cascade,
	guy		text	not null,
	sub_date	text	default (datetime('now')),	-- "YYYY-MM-DD HH:MM:SS.SSS"
	primary key (ml, guy)
);

create table moderators (
	ml		text	not null references ml(addr) on delete cascade on update cascade,
	guy		text	not null,
	primary key (ml, guy)
);

create table unsubscribed (
	ml		text	not null,
	guy		text	not null,
	unsub_date	text	default (datetime('now')),
	was		text	not null
);

------------------------
-- >> Small how-to << --
------------------------

-- create a new mailing list
--	insert into ml(addr, publi, moderated, addr) values (...);

-- insert some random $guy to the mailing list $m:
--	insert into subs(ml, guy) values ($ml, $guy);

-- add a $moderator to mailing list $ml
--	insert into moderators(ml, guy) values ($ml, $moderator);

-- unsubscribe a $guy from the mailing list $ml
--	delete from subs where ml = '$ml' and guy = '$guy';
