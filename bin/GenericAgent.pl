#!/usr/bin/perl -w
# --
# bin/GenericAgent.pl - a generic agent -=> e. g. close ale emails in a specific queue
# Copyright (C) 2002 Martin Edenhofer <martin+code@otrs.org>
# --
# $Id: GenericAgent.pl,v 1.1 2002-07-13 14:03:46 martin Exp $
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
# --

# use ../ as lib location
use FindBin qw($Bin);
use lib "$Bin/../";

use strict;

use vars qw($VERSION);
$VERSION = '$Revision: 1.1 $';
$VERSION =~ s/^.*:\s(\d+\.\d+)\s.*$/$1/;

use Kernel::Config;
use Kernel::System::Log;
use Kernel::System::DB;
use Kernel::System::Ticket;
use Kernel::System::Article;
use Kernel::System::Queue;

# --
# config
# --
my $UserIDOfGenericAgent = 1;
my %Jobs = (
   # --
   # [name of job] -> close all tickets in queue spam
   # --
   'close spam' => {
      # get all tickets with this properties  
      Queue => 'spam',
      States => ['new', 'open'],
      Locks => ['unlock'],
      # new ticket properties (no option is required, use just the options
      # witch should be changed!)
      New => {
        # new queue
        Queue => 'spam',
        # possible states (closed succsessful|closed unsuccsessful|open|new|removed) 
        State => 'closed succsessful',
        # new ticket owner (if needed)
        Owner => 'root@localhost',
        # if you want to add a Note
        Note => {
          From => 'GenericAgent',
          Subject => 'spam!',
          Body => 'Closed by GenericAgent.pl because it is spam!',
       },
       # new lock state
       Lock => 'unlock',
     },
   },
   # --
   # [name of job] -> move all tickets from tricky to exters
   # --
   'move tickets from tricky to experts' => {
      # get all tickets with this properties  
      Queue => 'tricky',
      States => ['new', 'open'],
      Locks => ['unlock'],
      # new ticket properties
      New => {
        Queue => 'experts',
        Note => {
          From => 'GenericAgent',
          Subject => 'Moved!',
          Body => 'Moved vrom "tricky" to "experts" because it was not possible to find a sollution!',
       },
     },
   },
);

# --
# common objects
# --
my %CommonObject = ();
$CommonObject{ConfigObject} = Kernel::Config->new();
$CommonObject{LogObject} = Kernel::System::Log->new(
    LogPrefix => 'OpenTRS-GenericAgent.pl',
);
$CommonObject{DBObject} = Kernel::System::DB->new(%CommonObject);
$CommonObject{TicketObject} = Kernel::System::Ticket->new(%CommonObject);
$CommonObject{ArticleObject} = Kernel::System::Article->new(%CommonObject);
$CommonObject{QueueObject} = Kernel::System::Queue->new(%CommonObject);

foreach my $Job (keys %Jobs) {
    print "$Job:\n";
    # get tickets w
    my %Tickets = $CommonObject{QueueObject}->GetTicketIDsByQueue(
        %{$Jobs{$Job}},
    );
    # set new ticket properties
    foreach (keys %Tickets) {
        print "* $Tickets{$_} ($_) \n";
        # --
        # move ticket
        # --
        if ($Jobs{$Job}->{New}->{Queue}) {
          print "  - Move Ticket to Queue $Jobs{$Job}->{New}->{Queue}\n";
          $CommonObject{TicketObject}->MoveByTicketID(
            QueueID => $CommonObject{QueueObject}->QueueLookup(Queue=>$Jobs{$Job}->{New}->{Queue}),
            UserID => $UserIDOfGenericAgent,
            TicketID => $_,
          );
        }
        # --
        # add note if wanted
        # --
        if ($Jobs{$Job}->{New}->{Note}->{Body}) {
          print "  - Add note\n";
          $CommonObject{ArticleObject}->CreateArticle(
            TicketID => $_,
            ArticleType => 'note-internal',
            SenderType => 'agent',
            From => $Jobs{$Job}->{New}->{Note}->{From} || 'GenericAgent',
            Subject => $Jobs{$Job}->{New}->{Note}->{Subject} || 'Note',
            Body => $Jobs{$Job}->{New}->{Note}->{Body}, 
            UserID => $UserIDOfGenericAgent,
            HistoryType => 'AddNote',
            HistoryComment => 'Note added.',
          );
        # --   
        # set new state
        # --
        if ($Jobs{$Job}->{New}->{State}) {
          print "  - set state to $Jobs{$Job}->{New}->{State}\n";
          $CommonObject{TicketObject}->SetState(
            TicketID => $_,
            UserID => $UserIDOfGenericAgent,
            State => $Jobs{$Job}->{New}->{State}, 
          );
        }
        # --
        # set new owner
        # --
        if ($Jobs{$Job}->{New}->{Owner}) {
          print "  - set owner to $Jobs{$Job}->{New}->{Owner}\n";
          $CommonObject{TicketObject}->SetOwner(
            TicketID => $_,
            UserID => $UserIDOfGenericAgent,
            NewUser => $Jobs{$Job}->{New}->{Owner},
          );
        }
        # --
        # set new lock 
        # --
        if ($Jobs{$Job}->{New}->{Lock}) {
          print "  - set lock to $Jobs{$Job}->{New}->{Lock}\n";
          $CommonObject{TicketObject}->SetLock(
            TicketID => $_,
            UserID => $UserIDOfGenericAgent,
            Lock => $Jobs{$Job}->{New}->{Lock},
          );

        }
      }
    }
}
