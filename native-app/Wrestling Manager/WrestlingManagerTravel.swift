import Foundation
import UIKit
import WebKit
import MapKit
import CoreLocation

// Foreground, one-shot travel estimates. No location tracking or route history.
@MainActor
final class WrestlingManagerTravelBridge: NSObject, WKScriptMessageHandler, CLLocationManagerDelegate {
    private weak var webView: WKWebView?
    private var manager: CLLocationManager?
    private var search: MKLocalSearch?
    private var directions: MKDirections?
    private var timeout: Task<Void, Never>?
    private var operation: UUID?
    private var requestID: String?
    private var destination: MKMapItem?
    private var stopMinutes: Double = 0
    private var waitingForLocation = false

    private func trusted(_ url: URL?) -> Bool {
        WrestlingManagerAppOrigin.contains(url)
    }
    func attach(to webView: WKWebView) { self.webView = webView }
    func detach() { cancel(); webView = nil }
    func cancel() {
        let id = requestID
        cleanup()
        if let id { send(["requestId": id, "ok": false, "message": "ETA request cancelled. Tap Calculate ETA to try again."]) }
    }
    private func cleanup() {
        operation = nil; requestID = nil; waitingForLocation = false
        timeout?.cancel(); timeout = nil
        search?.cancel(); search = nil
        directions?.cancel(); directions = nil
        manager?.stopUpdatingLocation(); manager?.delegate = nil; manager = nil
        destination = nil
    }
    private func send(_ payload: [String: Any]) {
        guard let webView, trusted(webView.url), JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.wrestlingManagerTravelResult && window.wrestlingManagerTravelResult(\(json));", completionHandler: nil)
    }
    private func finish(_ payload: [String: Any], ticket: UUID) {
        guard operation == ticket, let id = requestID else { return }
        var result = payload; result["requestId"] = id
        cleanup(); send(result)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, trusted(message.frameInfo.request.url), trusted(webView?.url),
              let body = message.body as? [String: Any], let command = body["command"] as? String else { return }
        if command == "cancel" { cancel(); return }
        guard let id = body["requestId"] as? String, UUID(uuidString: id) != nil,
              ["search", "eta"].contains(command), UIApplication.shared.applicationState == .active else { return }
        cancel()
        let ticket = UUID(); operation = ticket; requestID = id
        timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 45_000_000_000) } catch { return }
            self?.finish(["ok": false, "message": "The estimate took too long. Check your connection, try again, or enter the arrival time yourself."], ticket: ticket)
        }
        if command == "search" {
            guard let query = body["query"] as? String, (3...250).contains(query.trimmingCharacters(in: .whitespacesAndNewlines).count) else {
                finish(["ok": false, "message": "Enter a school address or town and state."], ticket: ticket); return
            }
            let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query
            let task = MKLocalSearch(request: request); search = task
            task.start { [weak self] response, error in
                Task { @MainActor [weak self] in
                    guard let self, self.operation == ticket else { return }
                    guard error == nil, let items = response?.mapItems, !items.isEmpty else {
                        self.finish(["ok": false, "message": "No matching destination was found. Include the town and state or full street address."], ticket: ticket); return
                    }
                    let choices: [[String: Any]] = items.prefix(8).compactMap { item in
                        let coordinate = item.placemark.coordinate
                        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
                        return ["name": item.name ?? "Destination", "address": item.placemark.title ?? item.name ?? "Destination",
                                "latitude": coordinate.latitude, "longitude": coordinate.longitude,
                                "timeZone": item.timeZone?.identifier ?? ""]
                    }
                    self.finish(["ok": true, "choices": choices], ticket: ticket)
                }
            }
            return
        }
        guard let target = body["destination"] as? [String: Any],
              let latitude = target["latitude"] as? Double, let longitude = target["longitude"] as? Double,
              latitude.isFinite, longitude.isFinite, CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: latitude, longitude: longitude)),
              let minutes = body["stopMinutes"] as? Double, minutes.isFinite, (0...360).contains(minutes) else {
            finish(["ok": false, "message": "Choose a destination and valid remaining stop time."], ticket: ticket); return
        }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        item.name = String((target["name"] as? String ?? "Destination").prefix(250))
        if let zone = target["timeZone"] as? String { item.timeZone = TimeZone(identifier: zone) }
        destination = item; stopMinutes = minutes
        guard let usage = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String, !usage.isEmpty else {
            finish(["ok": false, "message": "Install the latest Xcode update to enable travel estimates."], ticket: ticket); return
        }
        let locationManager = CLLocationManager(); manager = locationManager
        locationManager.delegate = self; locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        requestLocationIfAllowed()
    }
    private func requestLocationIfAllowed() {
        guard let manager, let ticket = operation, destination != nil, !waitingForLocation, directions == nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            waitingForLocation = true; manager.requestLocation()
        case .denied, .restricted:
            finish(["ok": false, "message": "Location access is off. Enable it in Settings to calculate an ETA, or enter the arrival time yourself."], ticket: ticket)
        @unknown default:
            finish(["ok": false, "message": "Location is unavailable. Enter the arrival time yourself."], ticket: ticket)
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard self.manager === manager else { return }
        requestLocationIfAllowed()
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard self.manager === manager, let ticket = operation else { return }
        finish(["ok": false, "message": "Your current location could not be found. Try again or enter the arrival time yourself."], ticket: ticket)
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard self.manager === manager, let ticket = operation, waitingForLocation else { return }
        guard let destination,
              let location = locations.last, location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 5000, abs(location.timestamp.timeIntervalSinceNow) < 120 else {
            if let ticket = operation { finish(["ok": false, "message": "A recent, usable location was not available. Try again or enter the arrival time yourself."], ticket: ticket) }
            return
        }
        waitingForLocation = false; manager.stopUpdatingLocation()
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.destination = destination; request.transportType = .automobile
        let departure = Date().addingTimeInterval(stopMinutes * 60); request.departureDate = departure
        let task = MKDirections(request: request); directions = task
        let zone = destination.timeZone?.identifier ?? TimeZone.current.identifier
        task.calculateETA { [weak self] response, error in
            Task { @MainActor [weak self] in
                guard let self, self.operation == ticket else { return }
                guard error == nil, let response, response.expectedTravelTime.isFinite, response.expectedTravelTime >= 0 else {
                    self.finish(["ok": false, "message": "A driving route could not be calculated. Check the destination or enter your own arrival time."], ticket: ticket); return
                }
                self.finish(["ok": true, "travelSeconds": response.expectedTravelTime,
                             "arrivalAt": departure.addingTimeInterval(response.expectedTravelTime).timeIntervalSince1970 * 1000,
                             "calculatedAt": Date().timeIntervalSince1970 * 1000,
                             "timeZone": zone, "stopMinutes": self.stopMinutes], ticket: ticket)
            }
        }
    }
}
