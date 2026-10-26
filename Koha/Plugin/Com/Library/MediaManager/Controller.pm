package Koha::Plugin::Com::Library::MediaManager::Controller;

# Copyright 2026 Tahir Ali Channa
#
# This file is part of Media Asset Management (MAM) for Koha.
#
# It is free software; you can redistribute it and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
# License for more details.
#
# You should have received a copy of the GNU General Public License along with it; if not, see
# <https://www.gnu.org/licenses>.

use Modern::Perl;
use Mojo::Base 'Mojolicious::Controller';
use Koha::Plugin::Com::Library::MediaManager;
sub exchange {
    my ($c) = @_;
    $c->res->headers->cache_control('no-store');
    $c->res->headers->header('Pragma'=>'no-cache');
    $c->res->headers->header('Referrer-Policy'=>'no-referrer');
    my $plugin = eval { Koha::Plugin::Com::Library::MediaManager->new };
    return $c->render(status=>503,json=>{error=>'temporarily_unavailable'}) unless $plugin;
    # Plain HTTP only while the TEST-ONLY HTTP mode is enabled (Configure page or koha-conf.xml).
    return $c->render(status=>400,json=>{error=>'https_required'})
        unless $c->req->url->to_abs->scheme eq 'https' || eval { $plugin->_insecure_http };
    return $c->render(status=>413,json=>{error=>'invalid_request'}) if length($c->req->body) > 1024;
    my ($status,$body);
    my $ok = eval {
        ($status,$body) = $plugin->exchange($c->req->json,
            $c->req->headers->header('X-Media-Client'),
            $c->req->headers->header('X-Media-Secret'),
            $c->tx->remote_address // '');
        1;
    };
    ($status,$body) = (503,{error=>'temporarily_unavailable'}) unless $ok;
    $c->res->headers->header('Retry-After'=>'60') if $status == 429;
    return $c->render(status=>$status,json=>$body);
}
1;
