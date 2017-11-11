
Net::NATS::Streaming::Client - A Perl client for the NATS Streaming messaging system.


Basic Usage

This class is a subclass of Net::NATS::Client and delegates all networking
to the parent.
 
$client = Net::NATS::Streaming::Client->new(uri => 'nats://localhost:4222', cluster_name => 'test-cluster');

$client->connect() or die $!;

$client->publish_stream({ subject => 'foo', data => 'Hello, World!'});

$subscription = $client->subscribe_stream(
    { subject => 'foo' }, 
    sub {
        my ($message) = @_;
       printf("Received a message: %s\n", $message->data);
    })
);

$client->unsubscribe_stream($subscription);
 
$client->close_stream();

SEE ALSO

https://github.com/carwynmoore/perl-nats Net::NATS::Client

COPYRIGHT & LICENSE

Copyright (C) 2017 by Sergey Kolychev <sergeykolychev.github@gmail.com>
 
This library is licensed under Apache 2.0 license https://www.apache.org/licenses/LICENSE-2.0
