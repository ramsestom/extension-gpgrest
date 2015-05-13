package com.sempaigames.gplayrest;

#if (android || iphone)
import extension.webview.WebView;
#end

import haxe.ds.Option;
import haxe.Timer;
import openfl.events.*;
import openfl.Lib;
import openfl.net.*;
import promhx.Deferred;
import promhx.Promise;

#if cpp
import cpp.vm.Thread;
#end

#if neko
import neko.vm.Thread;
#end

enum AuthStatus {
	Ok;
	Failed;
	Pending;
}

class Auth {

	var clientId : String;
	var clientSecret : String;
	var storage : SharedObject;

	var pendingTokenPromise : Promise<String>;
	var token : String;
	var tokenExpireTime : Float;
	var authStatus : AuthStatus;

	public function new(clientId : String, clientSecret : String) {
		this.storage = SharedObject.getLocal("gplayrest");
		this.clientId = clientId;
		this.clientSecret = clientSecret;
		this.token = null;
		this.pendingTokenPromise = null;
		this.authStatus = Pending;
	}

	static var stripString = "http://localhost:8099/?";
	static var redirectUri = "http://localhost:8099/";

	function getAuthCode() : Promise<String> {
		var ret = new Deferred<String>();
		var clientId = "client_id=" + this.clientId;
		var responseType = "response_type=" + "code";

		var scope = "scope=" + StringTools.urlEncode("https://www.googleapis.com/auth/games");
		var authCodeUrl = 'https://accounts.google.com/o/oauth2/auth?${clientId}&${responseType}&${"redirect_uri="+redirectUri}&${scope}&include_granted_scopes=true';

		#if (android || iphone)

		WebView.onURLChanging = function(url : String) {
			if (StringTools.startsWith(url, stripString)) {
				var url = StringTools.replace(url, stripString, "");
				for (p in url.split("&")) {
					var pair = p.split("=");
					if (pair.length!=2) {
						continue;
					}
					if (pair[0]=="code") {
						ret.resolve(pair[1]);
					}
				}
			}
		}
		WebView.open(authCodeUrl, true, null, ["(http|https)://localhost(.*)"]);

		#else

		Thread.create(function() {
			var server = new HttpServer();
			server.onGet = function(socket, str) {
				if (ret.isResolved()) {
					server.stopClient(socket);
					return;
				}
				var code = ~/.*code=/.replace(str, "");
				code = code.split("&")[0];

				socket.write(
"<!DOCTYPE html>
<html>
<body>

<h1>My First Heading</h1>

<p>My first paragraph.</p>

</body>
</html>
");
				server.stopClient(socket);
				ret.resolve(code);
			};
			server.run("localhost", 8099);
		});
		
		Lib.getURL(new URLRequest(authCodeUrl));

		#end

		return ret.promise();
	}

	function getNewTokenUsingCode(code : String) : Promise<String> {
		var request = new URLRequest("https://www.googleapis.com/oauth2/v3/token");
		var variables = new URLVariables();
		var ret = new Deferred<String>();
		variables.grant_type = "authorization_code";
		variables.code = code;
		variables.client_id = clientId;
		variables.client_secret = clientSecret;
		variables.redirect_uri = redirectUri;
		request.data = variables;
		request.method = URLRequestMethod.POST;
		var loader = new URLLoader();
		loader.addEventListener(Event.COMPLETE, function(e : Event) {
			var response = haxe.Json.parse(e.target.data);
			var accessToken = response.access_token;
			var refreshToken = response.refresh_token;

			if (accessToken==null || refreshToken==null) {
				throw "Couldn't get auth tokens";
			}

			var expiresIn : Int = response.expires_in;

			this.token = accessToken;
			this.tokenExpireTime = Timer.stamp() + expiresIn;
			this.storage.data.refreshToken = refreshToken;
			this.storage.flush();

			ret.resolve(accessToken);
		});
		loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, function(e : HTTPStatusEvent) {
			if (e.status!=200) {
				//throw 'Refresh token error: ${e.status}';
				ret.throwError('getNewTokenUsingCode error: ${e.status}');
				//prom.reject('Refresh token error: ${e.status}');
			}
		});
		loader.load(request);
		return ret.promise();
	}

	function getNewTokenUsingRefreshToken(refreshToken : String) : Promise<String> {
		var ret = new Deferred<String>();
		var request = new URLRequest("https://www.googleapis.com/oauth2/v3/token");
		var variables = new URLVariables();
		variables.refresh_token = refreshToken;
		variables.client_id = clientId;
		variables.client_secret = clientSecret;
		variables.grant_type = "refresh_token";
		request.data = variables;
		request.method = URLRequestMethod.POST;
		var loader = new URLLoader();
		loader.addEventListener(Event.COMPLETE, function(e : Event) {
			var response = haxe.Json.parse(e.target.data);
			var accessToken = response.access_token;
			var expiresIn : Int = response.expires_in;
			this.token = accessToken;
			this.tokenExpireTime = Timer.stamp() + expiresIn;
			ret.resolve(accessToken);
		});

		loader.addEventListener(HTTPStatusEvent.HTTP_STATUS, function(e : HTTPStatusEvent) {
			if (e.status!=200) {
				//throw 'Refresh token error: ${e.status}';
				ret.throwError('Refresh token error: ${e.status}');
				//prom.reject('Refresh token error: ${e.status}');
			}
		});

		loader.load(request);
		return ret.promise();
	}

	function getNewToken() : Promise<String> {
		authStatus = Pending;
		var ret : Promise<String> = null;
		if (storage.data.refreshToken!=null) {
			// Use refresh token
			var tokenUsingRefresh = getNewTokenUsingRefreshToken(storage.data.refreshToken);
			var dRet = new Deferred<String>();
			tokenUsingRefresh.catchError(function (x){
				trace("error using refresh token, retrying with auth code");
				getAuthCode().pipe(getNewTokenUsingCode).then(function(token) {
					dRet.resolve(token);
				});
			}).then(function (token){
				dRet.resolve(token);
			});
			ret = dRet.promise();
		} else {
			// No refresh_token:
			ret = getAuthCode().pipe(getNewTokenUsingCode);
		}
		ret.catchError(function(x) { trace('error: $x'); authStatus = Failed; return 'err'; }).then(function(_) authStatus = Ok);
		return ret;
	}

	public function getToken() : Promise<String> {
		if (token!=null && Timer.stamp()<tokenExpireTime) {
			var ret = new Deferred<String>();
			ret.resolve(token);
			return ret.promise();
		} else if (this.pendingTokenPromise!=null) {
			return this.pendingTokenPromise;
		} else {
			this.pendingTokenPromise = getNewToken();
			pendingTokenPromise.then(function(token) trace("token: " + token));
			return this.pendingTokenPromise;
		}
	}

}
