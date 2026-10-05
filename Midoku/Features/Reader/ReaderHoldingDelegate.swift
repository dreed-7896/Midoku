//
//  ReaderHoldingDelegate.swift
//  Midoku (iOS)
//
//  Created by Skitty on 8/16/22.
//

import Foundation
import AidokuRunner
import UIKit

protocol ReaderHoldingDelegate: AnyObject {
    var barsHidden: Bool { get }

    func hideBars()

    func getNextChapter() -> AidokuRunner.Chapter?
    func getPreviousChapter() -> AidokuRunner.Chapter?
    func setChapter(_ chapter: AidokuRunner.Chapter)
    func collectionCoverActions(image: UIImage, chapterKey: String, imageURL: String?) -> [UIAction]
    func bookmarkPanelAction(image: UIImage, chapterKey: String, page: Int) -> UIAction

    func setCurrentPage(_ page: Int, position: Double?)
    func setCurrentPages(_ pages: ClosedRange<Int>)
    func setPages(_ pages: [Page])
    func displayPage(_ page: Int) // show page on toolbar but don't set it as current page
    func setSliderOffset(_ offset: CGFloat)
    func setCompleted()
}
