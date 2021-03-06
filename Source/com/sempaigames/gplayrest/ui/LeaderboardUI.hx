package com.sempaigames.gplayrest.ui;

import com.sempaigames.gplayrest.GPlay;
import flash.events.*;
import flash.display.Sprite;
import flash.Lib;
import ru.stablex.ui.widgets.*;
import ru.stablex.ui.UIBuilder;
import com.sempaigames.gplayrest.datatypes.Leaderboard;
import com.sempaigames.gplayrest.datatypes.LeaderboardScores;
import com.sempaigames.gplayrest.datatypes.TimeSpan;
import openfl.system.Capabilities;

class LeaderboardUI extends UI {

	var leaderboard : Widget;
	var loading : Widget;

	var gPlay : GPlay;
	var leaderboardId : String;

	var nextPageToken : String;
	var isLoading : Bool;
	var isFirstLoad : Bool;
	var errorCount : Int;

	var displayingTimeSpan : TimeSpan;
	var loadedTimeSpan : TimeSpan;
	var displayingRankType : LeaderBoardCollection;
	var loadedRankType : LeaderBoardCollection;

	var freed : Bool;

	public function new(gPlay : GPlay, leaderboardId : String) {
		super();
		Stablex.init();
		freed = false;

		loading = UIBuilder.buildFn('com/sempaigames/gplayrest/ui/xml/loading.xml')();
		leaderboard = UIBuilder.buildFn('com/sempaigames/gplayrest/ui/xml/leaderboard.xml')();
		nextPageToken = "";
		isLoading = true;
		isFirstLoad = true;
		errorCount = 0;

		this.gPlay = gPlay;
		this.leaderboardId = leaderboardId;

		this.addChild(loading);

		displayingTimeSpan = loadedTimeSpan = TimeSpan.ALL_TIME;
		displayingRankType = loadedRankType = LeaderBoardCollection.PUBLIC;

		//#if mobile
		gPlay.Leaderboards_get(leaderboardId)
			.catchError(function(err) {
				isLoading = false;
				UIManager.getInstance().onNetworkError();
			}).then(function (leaderboard) {
				updateTitleBar(leaderboard.iconUrl, leaderboard.name);
				isLoading = false;
			});
		// #else
		// haxe.Timer.delay(function() {
		// 	var leaderboard = new Leaderboard(Stablex.getGamesLeaderBoard());
		// 	updateTitleBar(leaderboard.iconUrl, leaderboard.name);
		// 	isLoading = false;
		// }, 1000);
		// #end

	}

	override public function onResize(_) {
		var scale = Capabilities.screenDPI / 114;
		var scale = 1;

		loading.w = sx;
		loading.h = sy;
		leaderboard.w = sx/scale;
		leaderboard.h = sy/scale;

		var titleBar = leaderboard.getChildAs("leaderboard_backbar", TitleBar);
		var entriesBox = leaderboard.getChildAs("leaderboard_player_entries", VBox);
		titleBar.leftMargin = entriesBox.x;
		titleBar.rightMargin = Lib.current.stage.stageWidth - (entriesBox.x + entriesBox.w);
		titleBar.onResize();

		loading.refresh();
		leaderboard.refresh();
	}

	function onEnterFrame() {
		var scroll = leaderboard.getChildAs("scroll", Scroll);
		if (displayingRankType!=loadedRankType || displayingTimeSpan!=loadedTimeSpan) {
			clearResults();
			isFirstLoad = true;
			nextPageToken = "";
		}
		if (scroll.h - scroll.box.h - scroll.scrollY >= 0 && !isLoading && errorCount<5 &&
			(nextPageToken!="" || isFirstLoad) && nextPageToken!=null) {

			isLoading = true;
			isFirstLoad = false;
			var loadingRankType = LeaderBoardCollection.createByIndex(displayingRankType.getIndex());
			var loadingTimeSpan = TimeSpan.createByIndex(displayingTimeSpan.getIndex());

			//#if mobile
				gPlay.Scores_list(loadingRankType, leaderboardId, loadingTimeSpan, 25, nextPageToken)
					.catchError(function(err) {
						trace("Error :'( " + err + ", err count: " + errorCount);
						isLoading = false;
						errorCount++;
					}).then(function (scores) {
						addResults(scores);
						nextPageToken = scores.nextPageToken;
						loadedRankType = loadingRankType;
						loadedTimeSpan = loadingTimeSpan;
						isLoading = false;
					});
			// #else
			// 	haxe.Timer.delay(function() {
			// 		var scores = new LeaderboardScores(Stablex.getLeaderBaordScores());
			// 		addResults(scores);
			// 		nextPageToken = scores.nextPageToken;
			// 		loadedRankType = loadingRankType;
			// 		loadedTimeSpan = loadingTimeSpan;
			// 		isLoading = false;
			// 	}, 3000);
			// #end

		}
	}

	function onTimeLapseChange(timeSpan : Dynamic) {
		errorCount = 0;
		switch (timeSpan) {
			case 1: displayingTimeSpan = TimeSpan.ALL_TIME;
			case 2: displayingTimeSpan = TimeSpan.WEEKLY;
			case 3: displayingTimeSpan = TimeSpan.DAILY;
			default: {}
		}
	}

	function onRankTypeChange(leaderboardCollection : Dynamic) {
		errorCount = 0;
		switch (leaderboardCollection) {
			case 1: displayingRankType = LeaderBoardCollection.PUBLIC;
			case 2: displayingRankType = LeaderBoardCollection.SOCIAL;
			default: {}
		}
	}

	function clearResults() {
		if (freed) {
			return;
		}
		var entriesBox = leaderboard.getChildAs("leaderboard_player_entries", VBox);
		while (entriesBox.numChildren>0) {
			var c = entriesBox.getChildAt(0);
			if (c!=null) {
				entriesBox.removeChild(c);
				cast(c, Widget).free();
			}
		}
	}

	function updateTitleBar(imageUrl : String, title : String) {
		//leaderboard.getChildAs("title_icon", UrlBmp).url = imageUrl;
		//leaderboard.getChildAs("title_text", Text).text = title;
		if (freed) {
			return;
		}
		var bmp = new UrlBmp();
		var titleBar = leaderboard.getChildAs("leaderboard_backbar", TitleBar);
		titleBar.title = title;
		bmp.w = titleBar.h*0.8;
		bmp.h = titleBar.h*0.8;
		bmp.x = titleBar.w - titleBar.h*0.9;
		bmp.y = titleBar.h/2 - bmp.h/2;
		bmp.url = imageUrl;
		titleBar.logoImg = bmp;
		
		this.removeChild(loading);
		
		this.removeChild(leaderboard);
		this.addChild(leaderboard);
		
		this.addChild(loading);
		
	}

	function addResults(results : LeaderboardScores) {
		if (freed) {
			return;
		}
		onResize(null);
		loading.visible = false;
		var entriesBox = leaderboard.getChildAs("leaderboard_player_entries", VBox);
		for (entry in results.items) {
			var entryUI = UIBuilder.buildFn('com/sempaigames/gplayrest/ui/xml/leaderboardentry.xml')();
			var rank = entryUI.getChildAs("entry_ranking", Text);
			var image = entryUI.getChildAs("entry_image", UrlBmp);
			var name = entryUI.getChildAs("entry_name", Text);
			var score = entryUI.getChildAs("entry_score", Text);
			rank.text = entry.formattedScoreRank;
			if (entry.player.avatarImageUrl!=null) {
				image.url = entry.player.avatarImageUrl;
			} else {
				image.bitmapData = Stablex.getAvatarDefaultBmp();
			}
			name.text = entry.player.displayName;
			score.text = entry.formattedScore;
			entriesBox.addChild(entryUI);
		}
	}

	override public function onClose() {
		freed = true;
		leaderboard.free();
		loading.free();
	}

	override public function onKeyUp(k : KeyboardEvent) {
		if (k.keyCode==27) {
			UIManager.getInstance().closeCurrentView();
		}
	}

}
