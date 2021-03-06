
Net::NATS::Streaming::Client - A Perl client for the NATS Streaming messaging system.


Basic Usage

    This class is a subclass of Net::NATS::Client and delegates all networking
    to the parent.

    use Net::NATS::Streaming::Client;
    
    $client = Net::NATS::Streaming::Client->new(uri => 'nats://localhost:4222');
    
    $client->connect() or die $!;
    
    $subscription = $client->subscribe_channel(
        { subject => 'foo' },
        sub { warn shift->data }
    );

    $client->publish_channel({ subject => 'foo', data => 'Hello, World!'});

    $client->unsubscribe_channel($subscription);

    $client->close_stream();

SEE ALSO

https://github.com/carwynmoore/perl-nats Net::NATS::Client

COPYRIGHT & LICENSE

Copyright (C) 2017 by Sergey Kolychev <sergeykolychev.github@gmail.com>
 
This library is licensed under Apache 2.0 license https://www.apache.org/licenses/LICENSE-2.0
