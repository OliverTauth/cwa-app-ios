// Corona-Warn-App
//
// SAP SE and all other contributors
// copyright owners license this file to you under the Apache
// License, Version 2.0 (the "License"); you may not use this
// file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import BackgroundTasks
import ExposureNotification
import UIKit
import Reachability

final class SceneDelegate: UIResponder, UIWindowSceneDelegate, RequiresAppDependencies {
	// MARK: Properties

	var window: UIWindow?

	private lazy var navigationController: UINavigationController = AppNavigationController()
	private var homeController: HomeViewController?
	var state = State(summary: nil, exposureManager: .init()) {
		didSet {
			homeController?.homeInteractor.state = .init(
				isLoading: false,
				exposureManager: state.exposureManager,
				risk: store.previousRisk ?? .initial
			)
		}
	}

	private var developerMenu: DMDeveloperMenu?

	private func enableDeveloperMenuIfAllowed(in controller: UIViewController) {
		developerMenu = DMDeveloperMenu(
			presentingViewController: controller,
			client: client,
			store: store,
			exposureManager: exposureManager
		)
		developerMenu?.enableIfAllowed()
	}

	private lazy var clientConfiguration: HTTPClient.Configuration = {
		guard
			let distributionURLString = store.developerDistributionBaseURLOverride,
			let submissionURLString = store.developerSubmissionBaseURLOverride,
			let verificationURLString = store.developerVerificationBaseURLOverride,
			let distributionURL = URL(string: distributionURLString),
			let verificationURL = URL(string: verificationURLString),
			let submissionURL = URL(string: submissionURLString) else {
			return .production
		}

		return HTTPClient.Configuration(
			apiVersion: "v1",
			country: "DE",
			endpoints: HTTPClient.Configuration.Endpoints(
				distribution: .init(baseURL: distributionURL, requiresTrailingSlash: false),
				submission: .init(baseURL: submissionURL, requiresTrailingSlash: true),
				verification: .init(baseURL: verificationURL, requiresTrailingSlash: false)
			)
		)
	}()

	private(set) lazy var client: Client = {
		// We disable app store checks to make testing easier.
		//        #if APP_STORE
		//        return HTTPClient(configuration: .production)
		//        #endif
		return HTTPClient(configuration: self.clientConfiguration)
	}()

	private var enStateHandler: ENStateHandler?

	// MARK: UISceneDelegate

	func scene(_ scene: UIScene, willConnectTo _: UISceneSession, options _: UIScene.ConnectionOptions) {
		guard let windowScene = (scene as? UIWindowScene) else { return }
		let window = UIWindow(windowScene: windowScene)
		self.window = window

		exposureManager.resume(observer: self)

		UNUserNotificationCenter.current().delegate = self

		setupUI()

		NotificationCenter.default.addObserver(self, selector: #selector(isOnboardedDidChange(_:)), name: .isOnboardedDidChange, object: nil)

		NotificationCenter
			.default
			.addObserver(
				self,
				selector: #selector(exposureSummaryDidChange(_:)),
				name: .didDetectExposureDetectionSummary,
				object: nil
			)
	}

	func sceneWillEnterForeground(_ scene: UIScene) {
		let state = exposureManager.preconditions()
		let newState = ExposureManagerState(
				authorized: ENManager.authorizationStatus == .authorized,
				enabled: state.enabled,
				status: state.status
		)
		updateExposureState(newState)
	}


	func sceneDidBecomeActive(_: UIScene) {
		hidePrivacyProtectionWindow()
		UIApplication.shared.applicationIconBadgeNumber = 0
	}

	func sceneWillResignActive(_: UIScene) {
		showPrivacyProtectionWindow()
	}

	func sceneDidEnterBackground(_ scene: UIScene) {
		taskScheduler.scheduleBackgroundTaskRequests()
	}

	// MARK: Helper

	func requestUpdatedExposureState() {
		let state = exposureManager.preconditions()
		let newState = ExposureManagerState(
				authorized: ENManager.authorizationStatus == .authorized,
				enabled: state.enabled,
				status: state.status
		)
		updateExposureState(newState)
	}

	private func setupUI() {
		setupNavigationBarAppearance()

		if (exposureManager is MockExposureManager) && UserDefaults.standard.value(forKey: "isOnboarded") as? String == "NO" {
			showOnboarding()
		} else if !store.isOnboarded {
			showOnboarding()
		} else {
			showHome()
		}
		UIImageView.appearance().accessibilityIgnoresInvertColors = true
		window?.rootViewController = navigationController
		window?.makeKeyAndVisible()
	}

	private func setupNavigationBarAppearance() {
		let appearance = UINavigationBar.appearance()
		appearance.tintColor = .enaColor(for: .tint)
		appearance.titleTextAttributes = [
			NSAttributedString.Key.foregroundColor: UIColor.enaColor(for: .textPrimary1)
		]
		appearance.largeTitleTextAttributes = [
			NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .largeTitle).scaledFont(size: 28, weight: .bold),
			NSAttributedString.Key.foregroundColor: UIColor.enaColor(for: .textPrimary1)
		]
	}

	private func showHome(animated _: Bool = false) {
		if exposureManager.preconditions().status == .unknown {
			exposureManager.activate { [weak self] error in
				if let error = error {
					// TODO: Error handling, if error occurs, what can we do?
					logError(message: "Cannot activate the  ENManager. The reason is \(error)")
					return
				}
				self?.presentHomeVC()
			}
		} else {
			presentHomeVC()
		}
	}


	private func presentHomeVC() {
		enStateHandler = ENStateHandler(
			initialExposureManagerState: exposureManager.preconditions(),
			reachabilityService: ConnectivityReachabilityService(
				connectivityURLs: [clientConfiguration.configurationURL]
			),
			delegate: self
		)
		
		guard let enStateHandler = self.enStateHandler else {
			fatalError("It should not happen.")
		}

		let vc = AppStoryboard.home.initiate(viewControllerType: HomeViewController.self) { [unowned self] coder in
			HomeViewController(
				coder: coder,
				delegate: self,
				initialEnState: enStateHandler.state
			)
		}

		homeController = vc // strong ref needed
		homeController?.homeInteractor.state.exposureManager = state.exposureManager
		UIView.transition(with: navigationController.view, duration: CATransaction.animationDuration(), options: [.transitionCrossDissolve], animations: {
			self.navigationController.setViewControllers([vc], animated: false)
		})
		enableDeveloperMenuIfAllowed(in: vc)
	}

	private func showOnboarding() {
		navigationController.navigationBar.prefersLargeTitles = false
		navigationController.setViewControllers(
			[
				AppStoryboard.onboarding.initiateInitial { [unowned self] coder in
					OnboardingInfoViewController(
						coder: coder,
						pageType: .togetherAgainstCoronaPage,
						exposureManager: self.exposureManager,
						store: self.store
					)
				}
			],
			animated: false
		)
	}

	@objc
	func isOnboardedDidChange(_: NSNotification) {
		store.isOnboarded ? showHome() : showOnboarding()
	}

	@objc
	func exposureSummaryDidChange(_ notification: NSNotification) {
		guard let summary = notification.userInfo?["summary"] as? ENExposureDetectionSummary else {
			fatalError("received invalid summary notification. this is a programmer error")
		}
		state.summary = summary
		updateExposureState(state.exposureManager)
	}

	func scene(_: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
		// We have to allow backend configuration via the url schema for now.
		//        #if APP_STORE
		//        return
		//        #endif

		guard let url = URLContexts.first?.url else {
			return
		}

		guard let components = NSURLComponents(
			url: url,
			resolvingAgainstBaseURL: true
		),
			let query = components.queryItems else {
			return
		}

		if let submissionBaseURL = query.valueFor(queryItem: "submissionBaseURL") {
			store.developerSubmissionBaseURLOverride = submissionBaseURL
		}
		if let distributionBaseURL = query.valueFor(queryItem: "distributionBaseURL") {
			store.developerDistributionBaseURLOverride = distributionBaseURL
		}
		if let verificationBaseURL = query.valueFor(queryItem: "verificationBaseURL") {
			store.developerVerificationBaseURLOverride = verificationBaseURL
		}
		
	}

	private var privacyProtectionWindow: UIWindow?
}

// MARK: Privacy Protection
extension SceneDelegate {
	private func showPrivacyProtectionWindow() {
		guard
			let windowScene = window?.windowScene,
			store.isOnboarded == true
			else {
				return
		}
		let privacyProtectionViewController = PrivacyProtectionViewController()
		privacyProtectionWindow = UIWindow(windowScene: windowScene)
		privacyProtectionWindow?.rootViewController = privacyProtectionViewController
		privacyProtectionWindow?.windowLevel = .alert + 1
		privacyProtectionWindow?.makeKeyAndVisible()
		privacyProtectionViewController.show()
	}

	private func hidePrivacyProtectionWindow() {
		guard let privacyProtectionViewController = privacyProtectionWindow?.rootViewController as? PrivacyProtectionViewController else {
			return
		}
		privacyProtectionViewController.hide {
			self.privacyProtectionWindow?.isHidden = true
			self.privacyProtectionWindow = nil
		}
	}
}

extension SceneDelegate: ENAExposureManagerObserver {
	func exposureManager(
		_: ENAExposureManager,
		didChangeState newState: ExposureManagerState
	) {
		// Add the new state to the history
		store.tracingStatusHistory = store.tracingStatusHistory.consumingState(newState)
		riskProvider.exposureManagerState = newState

		let message = """
		New status of EN framework:
		Authorized: \(newState.authorized)
		enabled: \(newState.enabled)
		status: \(newState.status)
		authorizationStatus: \(ENManager.authorizationStatus)
		"""
		log(message: message)
		
		state.exposureManager = newState
		updateExposureState(newState)
	}
}

extension SceneDelegate: HomeViewControllerDelegate {
	/// Resets all stores and notifies the Onboarding.
	func homeViewControllerUserDidRequestReset(_: HomeViewController) {
		store.clearAll()
		UIApplication.coronaWarnDelegate().downloadedPackagesStore.reset()
		NotificationCenter.default.post(name: .isOnboardedDidChange, object: nil)
	}

	func homeViewControllerStartExposureTransaction(_: HomeViewController) {
		UIApplication.coronaWarnDelegate().appStartExposureDetectionTransaction()
	}
}

extension SceneDelegate: UNUserNotificationCenterDelegate {
	func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		completionHandler([.alert, .badge, .sound])
	}

	func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		switch response.notification.request.identifier {
		case ENATaskIdentifier.detectExposures.backgroundTaskSchedulerIdentifier:
			log(message: "Handling notification for \(response.notification.request.identifier)")

			switch response.actionIdentifier {
			case UserNotificationAction.openExposureDetectionResults.rawValue: showHome(animated: true)
			case UserNotificationAction.openTestResults.rawValue: showHome(animated: true)
			case UserNotificationAction.ignore.rawValue: break
			case UNNotificationDefaultActionIdentifier: break
			case UNNotificationDismissActionIdentifier: break
			default: break
			}

		default:
			log(message: "Handling notification for \(response.notification.request.identifier)")
		}

		completionHandler()
	}
}

private extension Array where Element == URLQueryItem {
	func valueFor(queryItem named: String) -> String? {
		first(where: { $0.name == named })?.value
	}
}

extension SceneDelegate {
	struct State {
		var summary: ENExposureDetectionSummary?
		var exposureManager: ExposureManagerState
	}
}

extension SceneDelegate: ExposureStateUpdating {
	func updateExposureState(_ state: ExposureManagerState) {
		homeController?.updateExposureState(state)
		enStateHandler?.updateExposureState(state)
	}
}

extension SceneDelegate: ENStateHandlerUpdating {
	func updateEnState(_ state: ENStateHandler.State) {
		log(message: "SceneDelegate got EnState update: \(state)")
		homeController?.updateEnState(state)
	}
}
