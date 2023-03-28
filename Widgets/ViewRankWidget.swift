import SwiftUI
import WidgetKit
import Intents
import ValorantAPI
import HandyOperators

struct ViewRankWidget: Widget {
	var body: some WidgetConfiguration {
		IntentConfiguration.preloading(
			kind: "view rank",
			intent: ViewRankIntent.self,
			provider: RankEntryProvider(),
			supportedFamilies: .systemSmall, .systemMedium
		) { entry in
			RankEntryView(entry: entry)
		}
		.configurationDisplayName("Rank")
		.description("View your current rank.")
	}
}

struct RankEntryView: TimelineEntryView {
	var entry: RankEntryProvider.Entry
	
	@Environment(\.adjustedWidgetFamily) private var widgetFamily
	@Environment(\.assets) private var assets
	@CurrentGameConfig private var gameConfig
	
	var isSmall: Bool {
		widgetFamily == .systemSmall
	}
	
	func contents(for info: RankInfo) -> some View {
		HStack {
			currentRank(info: info)
			
			if !isSmall {
				peakRank(summary: info.summary)
			}
		}
		.padding()
		.foregroundColor(.white)
		.background {
			RankInfoView.darkenedBackground(for: info.tierInfo)
		}
	}
	
	func currentRank(info: RankInfo) -> some View {
		VStack {
			let act = $gameConfig.seasons?.currentAct()
			
			column(
				season: act?.id,
				content: { size in
					RankInfoView(
						summary: info.summary,
						size: size,
						lineWidth: size / 16,
						shouldFallBackOnPrevious: isSmall
					)
				},
				rank: info.tierInfo,
				footer: {
					let current = info.summary.competitiveInfo?.inSeason(act?.id)
					if let current, current.leaderboardRank > 0 {
						Text("Rank \(current.leaderboardRank)")
					} else {
						Text("\(info.rankedRating) RR")
					}
				}
			)
		}
	}
	
	@ViewBuilder
	func peakRank(summary: CareerSummary) -> some View {
		if
			let seasons = $gameConfig.seasons,
			let peakRank = summary.peakRank(seasons: seasons),
			let info = seasons.tierInfo(peakRank)
		{
			column(
				season: peakRank.season,
				content: { size in
					PeakRankIcon(
						peakRank: peakRank, tierInfo: info,
						size: size,
						borderOpacity: 0.7,
						borderBlendMode: .plusLighter
					)
				},
				rank: info,
				footer: {
					Text("Lifetime Peak")
				}
			)
		}
	}
	
	func column<Content: View, Footer: View>(
		season: Season.ID?,
		@ViewBuilder content: @escaping (CGFloat) -> Content,
		rank: CompetitiveTier?,
		@ViewBuilder footer: () -> Footer
	) -> some View {
		VStack {
			let shouldShowActName = configuration.showActName != 0
			let shouldShowRankName = configuration.showRankName != 0
			let shouldShowRankRating = configuration.showRankRating != 0
			let hasTextBelow = shouldShowRankName || shouldShowRankRating
			
			if shouldShowActName, hasTextBelow { // looks stupid above with nothing below
				SeasonLabel(season: season)
					.font(.caption)
					.blendMode(.plusLighter)
			}
			
			GeometryReader { geometry in
				content(min(geometry.size.width, geometry.size.height))
					.frame(maxWidth: .infinity)
			}
			
			if shouldShowActName, !hasTextBelow {
				SeasonLabel(season: season)
					.font(.caption)
					.blendMode(.plusLighter)
			}
			
			if shouldShowRankName, let rank {
				Text(rank.name)
					.font(.callout.weight(.semibold))
					.opacity(0.8)
					.blendMode(.plusLighter)
			}
			
			if shouldShowRankRating {
				footer()
					.font(.caption)
					.foregroundStyle(.secondary)
					.blendMode(.plusLighter)
			}
		}
	}
}

#if DEBUG
struct ViewRankWidget_Previews: PreviewProvider {
	static let seasons = Managers.assets.assets?.seasons
	
	static var previews: some View {
		let view = RankEntryView(entry: .init(
			info: .success(.init(
				summary: PreviewData.summary,
				tierInfo: seasons?.with(PreviewData.gameConfig).currentTierInfo(number: 22),
				rankedRating: 69
			))
		))
		
		view.previewContext(WidgetPreviewContext(family: .systemSmall))
			.previewDisplayName("Small")
		
		view.previewContext(WidgetPreviewContext(family: .systemMedium))
			.previewDisplayName("Medium")
	}
}
#endif
