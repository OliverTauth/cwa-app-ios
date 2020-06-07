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

import UIKit

final class HomeInactiveRiskCellConfigurator: HomeRiskCellConfigurator {

	let identifier = UUID()

	private var lastInvestigation: String
	private var lastUpdateDate: Date?

	enum IncativeType {
		case noCalculationPossible
		case outdatedResults
	}

	var incativeType: IncativeType = .noCalculationPossible

	var activeAction: (() -> Void)?

	private static let lastUpdateDateFormatter: DateFormatter = {
		let dateFormatter = DateFormatter()
		dateFormatter.doesRelativeDateFormatting = true
		dateFormatter.dateStyle = .short
		dateFormatter.timeStyle = .short
		return dateFormatter
	}()

	private var lastUpdateDateString: String {
		if let lastUpdateDate = lastUpdateDate {
			return Self.lastUpdateDateFormatter.string(from: lastUpdateDate)
		} else {
			return AppStrings.Home.riskCardNoDateTitle
		}
	}

	// MARK: Creating a Home Risk Cell Configurator

	init(incativeType: IncativeType, lastInvestigation: String, lastUpdateDate: Date?) {
		self.incativeType = incativeType
		self.lastInvestigation = lastInvestigation
		self.lastUpdateDate = lastUpdateDate
	}

	// MARK: Configuration

	func configure(cell: RiskInactiveCollectionViewCell) {
		cell.delegate = self

		cell.removeAllArrangedSubviews()

		let title: String = incativeType == .noCalculationPossible ? AppStrings.Home.riskCardInactiveNoCalculationPossibleTitle : AppStrings.Home.riskCardInactiveOutdatedResultsTitle
		let titleColor: UIColor = .black
		cell.configureTitle(title: title, titleColor: titleColor)

		let bodyText: String = incativeType == .noCalculationPossible ? AppStrings.Home.riskCardInactiveNoCalculationPossibleBody : AppStrings.Home.riskCardInactiveOutdatedResultsBody
		cell.configureBody(text: bodyText, bodyColor: titleColor)

		let color = UIColor.white
		let separatorColor = UIColor.systemGray5
		var itemCellConfigurators: [HomeRiskViewConfiguratorAny] = []

		let lastInvestigationTitle = String(format: AppStrings.Home.riskCardInactiveActivateItemTitle, lastInvestigation)
		let iconTintColor = UIColor(red: 93.0 / 255.0, green: 111.0 / 255.0, blue: 128.0 / 255.0, alpha: 1.0)
		let item1 = HomeRiskImageItemViewConfigurator(title: lastInvestigationTitle, titleColor: titleColor, iconImageName: "Icons_LetzteErmittlung-Light", iconTintColor: iconTintColor, color: color, separatorColor: separatorColor)
		let dateTitle = String(format: AppStrings.Home.riskCardDateItemTitle, lastUpdateDateString)
		let item2 = HomeRiskImageItemViewConfigurator(title: dateTitle, titleColor: titleColor, iconImageName: "Icons_Aktualisiert", iconTintColor: iconTintColor, color: color, separatorColor: separatorColor)
		itemCellConfigurators.append(contentsOf: [item1, item2])

		cell.configureRiskViews(cellConfigurators: itemCellConfigurators)
		cell.configureBackgroundColor(color: color)

		let chevronImage = UIImage(systemName: "chevron.right")
		cell.configureChevron(image: chevronImage, tintColor: .lightGray)

		let buttonTitle: String = incativeType == .noCalculationPossible ? AppStrings.Home.riskCardInactiveNoCalculationPossibleButton : AppStrings.Home.riskCardInactiveOutdatedResultsButton

		cell.configureActiveButton(title: buttonTitle)

		setupAccessibility(cell)

	}

	func setupAccessibility(_ cell: RiskInactiveCollectionViewCell) {
		cell.titleLabel.isAccessibilityElement = false
		cell.chevronImageView.isAccessibilityElement = false
		cell.viewContainer.isAccessibilityElement = false
		cell.stackView.isAccessibilityElement = false

		cell.topContainer.isAccessibilityElement = true
		cell.bodyLabel.isAccessibilityElement = true

		let topContainerText = cell.titleLabel.text ?? ""
		cell.topContainer.accessibilityLabel = topContainerText
		cell.topContainer.accessibilityTraits = [.button, .header]
	}

}

extension HomeInactiveRiskCellConfigurator: RiskInactiveCollectionViewCellDelegate {
	func activeButtonTapped(cell: RiskInactiveCollectionViewCell) {
		activeAction?()
	}
}
