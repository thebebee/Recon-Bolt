import SwiftUI
import ValorantAPI

struct EventTimeline: View {
	let matchData: MatchViewData
	@Binding var roundData: RoundData
	
	private let markerHeight = 10.0
	private let iconDistance = 16.0
	private let iconSize = 18.0
	private let knobSize = 16.0
	
	var body: some View {
		let events = roundData.events
		if let firstEvent = events.first, let lastEvent = events.last {
			let heightFromBar = max(markerHeight, knobSize)
			let heightFromIcons = iconDistance + iconSize / 2
			
			GeometryReader { geometry in
				let barY = geometry.size.height - heightFromBar / 2
				
				let scaleFactor = geometry.size.width / lastEvent.position
				HStack(spacing: 0) {
					Rectangle().frame(width: 1, height: 6)
						.foregroundStyle(.secondary)
					Rectangle()
						.frame(width: scaleFactor * firstEvent.position - 1)
						.foregroundStyle(.secondary)
					Rectangle()
						.foregroundStyle(.secondary)
						.frame(width: scaleFactor * (roundData.currentPosition - firstEvent.position))
					Rectangle()
						.foregroundStyle(.tertiary)
						.foregroundColor(.primary)
				}
				.frame(height: 2)
				.position(x: geometry.size.width / 2, y: barY)
				.foregroundColor(.accentColor)
				
				ForEach(events) { event in
					eventCapsule(for: event)
						.position(x: scaleFactor * event.position, y: barY)
				}
				
				Circle()
					//.fill(.accentColor)
					.fill(Color.white)
					.frame(width: knobSize, height: knobSize)
					.shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
					//.background(Circle().padding(-2).blendMode(.destinationOut))
					.position(x: scaleFactor * roundData.currentPosition, y: barY)
					.gesture(
						DragGesture(minimumDistance: 0, coordinateSpace: .named(CoordSpace.slider))
							.onChanged { roundData.currentPosition = $0.location.x / scaleFactor }
					)
			}
			.coordinateSpace(name: CoordSpace.slider)
			.compositingGroup()
			.frame(height: heightFromBar + heightFromIcons)
			.fixedSize(horizontal: false, vertical: true)
			//.background(.red.opacity(0.1))
		}
	}
	
	private func eventCapsule(for event: PositionedEvent) -> some View {
		Capsule()
			.frame(width: 4, height: markerHeight)
			.fixedSize()
			.background {
				Capsule().padding(-1)
					.blendMode(.destinationOut)
			}
			.overlay {
				icon(for: event.event)
					.frame(width: iconSize, height: iconSize)
					//.background(.thinMaterial)
					.position(x: 2, y: -iconDistance)
			}
			.foregroundColor(event.relativeColor)
			.onTapGesture {
				withAnimation {
					roundData.currentPosition = event.position
				}
			}
	}
	
	@ViewBuilder
	private func icon(for event: RoundEvent) -> some View {
		if event is Kill {
			Image(systemName: "xmark")
				.resizable()
				.padding(2)
		} else if let bombEvent = event as? BombEvent {
			Image("\(bombEvent.isDefusal ? "Defuse" : "Spike") Icon")
				.resizable()
		}
	}
	
	private enum CoordSpace: Hashable {
		case slider
	}
}
