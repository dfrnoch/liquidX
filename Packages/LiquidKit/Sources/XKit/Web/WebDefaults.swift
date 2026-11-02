// Generated from x.com's web client on 2026-11-03. These are only fallbacks:
// at runtime `WebAPIConfig.discover` reads current values from x.com's main.js,
// and the login page reports the IDs the site itself uses.
// The x.com web API is unofficial; see docs/web-session.md.

enum WebDefaults {
    /// Feature switches sent with timeline-shaped queries (HomeTimeline, TweetDetail, ...).
    static let timelineFeatures: [String] = [
        "rweb_video_screen_enabled",
        "rweb_cashtags_enabled",
        "profile_label_improvements_pcf_label_in_post_enabled",
        "responsive_web_profile_redirect_enabled",
        "rweb_tipjar_consumption_enabled",
        "verified_phone_label_enabled",
        "creator_subscriptions_tweet_preview_api_enabled",
        "responsive_web_graphql_timeline_navigation_enabled",
        "premium_content_api_read_enabled",
        "communities_web_enable_tweet_community_results_fetch",
        "c9s_tweet_anatomy_moderator_badge_enabled",
        "responsive_web_grok_analyze_button_fetch_trends_enabled",
        "responsive_web_grok_analyze_post_followups_enabled",
        "rweb_cashtags_composer_attachment_enabled",
        "responsive_web_jetfuel_frame",
        "rweb_sports_post_context_enabled",
        "x_elections_post_context_enabled",
        "responsive_web_grok_share_attachment_enabled",
        "responsive_web_grok_annotations_enabled",
        "articles_preview_enabled",
        "responsive_web_edit_tweet_api_enabled",
        "rweb_conversational_replies_downvote_enabled",
        "graphql_is_translatable_rweb_tweet_is_translatable_enabled",
        "view_counts_everywhere_api_enabled",
        "longform_notetweets_consumption_enabled",
        "responsive_web_twitter_article_tweet_consumption_enabled",
        "content_disclosure_indicator_enabled",
        "content_disclosure_ai_generated_indicator_enabled",
        "responsive_web_grok_show_grok_translated_post",
        "responsive_web_grok_analysis_button_from_backend",
        "post_ctas_fetch_enabled",
        "freedom_of_speech_not_reach_fetch_enabled",
        "standardized_nudges_misinfo",
        "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled",
        "longform_notetweets_rich_text_read_enabled",
        "longform_notetweets_inline_media_enabled",
        "responsive_web_nested_quote_preview_enabled",
        "responsive_web_grok_image_annotation_enabled",
        "responsive_web_grok_imagine_annotation_enabled",
        "responsive_web_made_on_x_label_enabled",
        "responsive_web_grok_community_note_auto_translation_is_enabled",
        "responsive_web_enhance_cards_enabled",
    ]

    /// Feature switches that x.com currently sends as `false`; everything else is `true`.
    static let disabledFeatures: Set<String> = [
        "rweb_video_screen_enabled",
        "rweb_tipjar_consumption_enabled",
        "verified_phone_label_enabled",
        "premium_content_api_read_enabled",
        "responsive_web_grok_analyze_button_fetch_trends_enabled",
        "rweb_conversational_replies_downvote_enabled",
        "post_ctas_fetch_enabled",
        "longform_notetweets_inline_media_enabled",
        "responsive_web_made_on_x_label_enabled",
        "responsive_web_enhance_cards_enabled",
        "subscriptions_feature_can_gift_premium",
    ]

    /// Field toggle values as x.com sends them; unknown toggles default to `false`.
    static let fieldToggleValues: [String: Bool] = [
        "withArticleRichContentState": true,
        "withArticleSummaryText": true,
        "withArticleVoiceOver": true,
        "withAuxiliaryUserLabels": true,
    ]

    static let operations: [String: WebOperation] = [
        "HomeTimeline": WebOperation(
            queryId: "fedFLLzmiCAuzPgA8lyh8Q",
            features: timelineFeatures,
            fieldToggles: ["withPayments"]
        ),
        "HomeLatestTimeline": WebOperation(
            queryId: "GjleyyGw4xvWe5tn8EQt9w",
            features: timelineFeatures,
            fieldToggles: ["withPayments"]
        ),
        "Bookmarks": WebOperation(
            queryId: "jbqsfdzI0EMFHAtpEC6vyA",
            features: timelineFeatures,
            fieldToggles: ["withPayments"]
        ),
        "UserByScreenName": WebOperation(
            queryId: "AMIBMjtxEEATh4z8V9GtRg",
            features: [
            "hidden_profile_subscriptions_enabled",
            "profile_label_improvements_pcf_label_in_post_enabled",
            "responsive_web_profile_redirect_enabled",
            "rweb_tipjar_consumption_enabled",
            "verified_phone_label_enabled",
            "subscriptions_verification_info_is_identity_verified_enabled",
            "subscriptions_verification_info_verified_since_enabled",
            "highlights_tweets_tab_ui_enabled",
            "responsive_web_twitter_article_notes_tab_enabled",
            "subscriptions_feature_can_gift_premium",
            "creator_subscriptions_tweet_preview_api_enabled",
            "responsive_web_graphql_timeline_navigation_enabled",
        ],
            fieldToggles: ["withPayments", "withDmBlocks", "withAuxiliaryUserLabels"]
        ),
        "UserOriginalsTimeline": WebOperation(
            queryId: "0L_XictlTdXhxJyxhMDxQA",
            features: timelineFeatures,
            fieldToggles: ["withPayments", "withDmBlocks", "withAuxiliaryUserLabels", "withArticleRichContentState", "withArticlePlainText", "withArticleSummaryText", "withArticleVoiceOver", "withGrokAnalyze", "withDisallowedReplyControls"]
        ),
        "UserTweets": WebOperation(
            queryId: "Rf0Oc_XSVYjASOj-Jbz3Xg",
            features: timelineFeatures,
            fieldToggles: ["withPayments", "withDmBlocks", "withAuxiliaryUserLabels", "withArticleRichContentState", "withArticlePlainText", "withArticleSummaryText", "withArticleVoiceOver", "withGrokAnalyze", "withDisallowedReplyControls"]
        ),
        "UserTweetsAndReplies": WebOperation(
            queryId: "a6fye5SJAFWPUhE2BzoxBQ",
            features: timelineFeatures,
            fieldToggles: ["withPayments", "withDmBlocks", "withAuxiliaryUserLabels", "withArticleRichContentState", "withArticlePlainText", "withArticleSummaryText", "withArticleVoiceOver", "withGrokAnalyze", "withDisallowedReplyControls"]
        ),
        "UserMedia": WebOperation(
            queryId: "frYNjZhGZmtrgXmi_tIMkA",
            features: timelineFeatures,
            fieldToggles: ["withPayments", "withDmBlocks", "withAuxiliaryUserLabels", "withArticleRichContentState", "withArticlePlainText", "withArticleSummaryText", "withArticleVoiceOver", "withGrokAnalyze", "withDisallowedReplyControls"]
        ),
        "TweetDetail": WebOperation(
            queryId: "qpemjmVMoTWDvcRT43JIVQ",
            features: timelineFeatures,
            fieldToggles: ["withPayments", "withDmBlocks", "withAuxiliaryUserLabels", "withArticleRichContentState", "withArticlePlainText", "withArticleSummaryText", "withArticleVoiceOver", "withGrokAnalyze", "withDisallowedReplyControls"]
        ),
        "TweetResultByRestId": WebOperation(
            queryId: "U8lc5aomF5krJzZ9vJ9wxg",
            features: [
            "creator_subscriptions_tweet_preview_api_enabled",
            "premium_content_api_read_enabled",
            "communities_web_enable_tweet_community_results_fetch",
            "c9s_tweet_anatomy_moderator_badge_enabled",
            "responsive_web_grok_analyze_button_fetch_trends_enabled",
            "responsive_web_grok_analyze_post_followups_enabled",
            "rweb_cashtags_composer_attachment_enabled",
            "responsive_web_jetfuel_frame",
            "rweb_sports_post_context_enabled",
            "x_elections_post_context_enabled",
            "responsive_web_grok_share_attachment_enabled",
            "responsive_web_grok_annotations_enabled",
            "articles_preview_enabled",
            "responsive_web_edit_tweet_api_enabled",
            "rweb_conversational_replies_downvote_enabled",
            "graphql_is_translatable_rweb_tweet_is_translatable_enabled",
            "view_counts_everywhere_api_enabled",
            "longform_notetweets_consumption_enabled",
            "responsive_web_twitter_article_tweet_consumption_enabled",
            "content_disclosure_indicator_enabled",
            "content_disclosure_ai_generated_indicator_enabled",
            "responsive_web_grok_show_grok_translated_post",
            "responsive_web_grok_analysis_button_from_backend",
            "post_ctas_fetch_enabled",
            "rweb_cashtags_enabled",
            "freedom_of_speech_not_reach_fetch_enabled",
            "standardized_nudges_misinfo",
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled",
            "longform_notetweets_rich_text_read_enabled",
            "longform_notetweets_inline_media_enabled",
            "profile_label_improvements_pcf_label_in_post_enabled",
            "responsive_web_profile_redirect_enabled",
            "rweb_tipjar_consumption_enabled",
            "verified_phone_label_enabled",
            "responsive_web_nested_quote_preview_enabled",
            "responsive_web_grok_image_annotation_enabled",
            "responsive_web_grok_imagine_annotation_enabled",
            "responsive_web_made_on_x_label_enabled",
            "responsive_web_grok_community_note_auto_translation_is_enabled",
            "responsive_web_graphql_timeline_navigation_enabled",
        ],
            fieldToggles: ["withArticleRichContentState", "withArticlePlainText", "withArticleSummaryText", "withArticleVoiceOver", "withGrokAnalyze", "withDisallowedReplyControls", "withPayments", "withDmBlocks", "withAuxiliaryUserLabels"]
        ),
        "SearchTimeline": WebOperation(
            queryId: "3fEctOs2-FvTB7_mvm1hrQ",
            features: timelineFeatures,
            fieldToggles: ["withPayments", "withDmBlocks", "withAuxiliaryUserLabels", "withArticleRichContentState", "withArticlePlainText", "withArticleSummaryText", "withArticleVoiceOver", "withGrokAnalyze", "withDisallowedReplyControls"]
        ),
        "FavoriteTweet": WebOperation(
            queryId: "lI07N6Otwv1PhnEgXILM7A",
            features: [],
            fieldToggles: []
        ),
        "UnfavoriteTweet": WebOperation(
            queryId: "ZYKSe-w7KEslx3JhSIk5LA",
            features: [],
            fieldToggles: []
        ),
        "CreateRetweet": WebOperation(
            queryId: "mbRO74GrOvSfRcJnlMapnQ",
            features: [],
            fieldToggles: []
        ),
        "DeleteRetweet": WebOperation(
            queryId: "ZyZigVsNiFO6v1dEks1eWg",
            features: [],
            fieldToggles: []
        ),
        "CreateBookmark": WebOperation(
            queryId: "aoDbu3RHznuiSkQ9aNM67Q",
            features: [],
            fieldToggles: []
        ),
        "DeleteBookmark": WebOperation(
            queryId: "Wlmlj2-xzyS1GN3a6cj-mQ",
            features: [],
            fieldToggles: []
        ),
        "CreateTweet": WebOperation(
            queryId: "l4hk8uVGvR-a8kzQ4nOhPA",
            features: [
            "premium_content_api_read_enabled",
            "communities_web_enable_tweet_community_results_fetch",
            "c9s_tweet_anatomy_moderator_badge_enabled",
            "responsive_web_grok_analyze_button_fetch_trends_enabled",
            "responsive_web_grok_analyze_post_followups_enabled",
            "rweb_cashtags_composer_attachment_enabled",
            "responsive_web_jetfuel_frame",
            "rweb_sports_post_context_enabled",
            "x_elections_post_context_enabled",
            "responsive_web_grok_share_attachment_enabled",
            "responsive_web_grok_annotations_enabled",
            "responsive_web_edit_tweet_api_enabled",
            "rweb_conversational_replies_downvote_enabled",
            "graphql_is_translatable_rweb_tweet_is_translatable_enabled",
            "view_counts_everywhere_api_enabled",
            "longform_notetweets_consumption_enabled",
            "responsive_web_twitter_article_tweet_consumption_enabled",
            "content_disclosure_indicator_enabled",
            "content_disclosure_ai_generated_indicator_enabled",
            "responsive_web_grok_show_grok_translated_post",
            "responsive_web_grok_analysis_button_from_backend",
            "post_ctas_fetch_enabled",
            "longform_notetweets_rich_text_read_enabled",
            "longform_notetweets_inline_media_enabled",
            "profile_label_improvements_pcf_label_in_post_enabled",
            "responsive_web_profile_redirect_enabled",
            "rweb_tipjar_consumption_enabled",
            "verified_phone_label_enabled",
            "responsive_web_nested_quote_preview_enabled",
            "articles_preview_enabled",
            "rweb_cashtags_enabled",
            "responsive_web_grok_community_note_auto_translation_is_enabled",
            "freedom_of_speech_not_reach_fetch_enabled",
            "standardized_nudges_misinfo",
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled",
            "responsive_web_grok_image_annotation_enabled",
            "responsive_web_grok_imagine_annotation_enabled",
            "responsive_web_made_on_x_label_enabled",
            "responsive_web_graphql_timeline_navigation_enabled",
        ],
            fieldToggles: ["withArticleRichContentState", "withArticlePlainText", "withArticleSummaryText", "withArticleVoiceOver", "withGrokAnalyze", "withDisallowedReplyControls", "withPayments", "withDmBlocks", "withAuxiliaryUserLabels"]
        ),
        "Viewer": WebOperation(
            queryId: "TpQxQtWMTMnIAMPlMGMqNw",
            features: [
            "subscriptions_upsells_api_enabled",
            "profile_label_improvements_pcf_label_in_post_enabled",
            "responsive_web_profile_redirect_enabled",
            "rweb_tipjar_consumption_enabled",
            "verified_phone_label_enabled",
            "creator_subscriptions_tweet_preview_api_enabled",
            "responsive_web_graphql_timeline_navigation_enabled",
        ],
            fieldToggles: ["isDelegate", "withPayments", "withDmBlocks", "withAuxiliaryUserLabels"]
        ),
    ]
}
