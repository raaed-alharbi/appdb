//
//  IPAWebViewController.swift
//  appdb
//
//  Created by ned on 10/05/2019.
//  Copyright © 2019 ned. All rights reserved.
//

import UIKit
import WebKit
import Cartography
import Alamofire

protocol IPAWebViewControllerDelegate: class {
    func didDismiss()
}

class IPAWebViewNavController: UINavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        modalPresentationStyle = .overFullScreen
    }
}

class IPAWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    
    fileprivate var webView: WKWebView!
    fileprivate var progressView: UIProgressView!
    
    fileprivate var delegate: IPAWebViewControllerDelegate?
    
    var appIcon: String = ""
    var url: URL!
    
    init(_ url: URL, _ appIcon: String = "", delegate: IPAWebViewControllerDelegate) {
        self.url = url
        self.appIcon = appIcon
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        webView = WKWebView()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        view = webView
        
        // Progress view
        progressView = UIProgressView()
        progressView.trackTintColor = .clear
        progressView.theme_progressTintColor = Color.mainTint
        progressView.progress = 0
        view.addSubview(progressView)
        
        // Add cancel button
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Cancel".localized(), style: .plain, target: self, action: #selector(self.dismissAnimated))
        
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.title), options: .new, context: nil)

        setConstraints()
        
        startLoading(request: URLRequest(url: url))
    }
    
    fileprivate func startLoading(request: URLRequest) {
        if #available(iOS 11, *) {
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "rules",
                encodedContentRuleList: blockRules) { (list, error) in
                    
                    guard let list = list, error == nil else {
                        self.webView.load(request)
                        return
                    }
                    self.webView.configuration.userContentController.add(list)
                    self.webView.load(request)
            }
        } else {
            webView.load(request)
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            progressView.alpha = 1
            progressView.setProgress(Float(webView.estimatedProgress), animated: true)
            if webView.estimatedProgress >= 1.0 {
                UIView.animate(withDuration: 0.2, delay: 0.7, options: .curveEaseOut, animations: {
                    self.progressView.alpha = 0
                }, completion: { _ in
                    self.progressView.setProgress(0, animated: false)
                })
            }
        }
        if keyPath == "title" {
            title = webView.title
        }
    }
    
    // MARK: - Constraints
    
    fileprivate var group: ConstraintGroup = ConstraintGroup()
    fileprivate func setConstraints() {
        
        // Calculate navBar + eventual Status bar height
        var offset: CGFloat = 0
        if let nav = navigationController {
            offset = nav.navigationBar.frame.height + UIApplication.shared.statusBarFrame.height
        }
        
        // Fixes hotspot status bar on non X devices
        if !Global.hasNotch, UIApplication.shared.statusBarFrame.height > 20.0 {
            offset -= (UIApplication.shared.statusBarFrame.height - 20.0)
        }
        
        constrain(progressView, replace: group) { progress in
            progress.top == progress.superview!.top + offset
            progress.left == progress.superview!.left
            progress.right == progress.superview!.right
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate(alongsideTransition: { (context: UIViewControllerTransitionCoordinatorContext!) -> Void in
            self.setConstraints()
        }, completion: nil)
    }
    
    // MARK: - Dismiss animated
    
    @objc func dismissAnimated() { dismiss(animated: true) }
    
}

extension IPAWebViewController {
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            
            guard let url = navigationAction.request.url, let host = url.host, let delegate = delegate else { return nil }
            
            if AdBlocker.shared.shouldBlock(host: host) {
                return nil
            } else {
                let webVc = IPAWebViewController(url, appIcon, delegate: delegate)
                self.navigationController?.pushViewController(webVc, animated: true)
            }
        }
        return nil
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        
        guard let url = navigationResponse.response.url, let filename = navigationResponse.response.suggestedFilename else { return }
        
        if filename.hasSuffix(".ipa") {
            
            decisionHandler(.cancel)
            webView.stopLoading()
            
            ObserveDownloadingApps.shared.addDownload(url: url.absoluteString, filename: filename, icon: appIcon)
            dismissAnimated()
            delegate?.didDismiss()

            return
        }
        
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        
        // todo itunes
        
        if url.absoluteString.hasPrefix("itms-services://") || url.absoluteString.hasPrefix("https://itunes.apple.com") {
            UIApplication.shared.openURL(url)
            decisionHandler(.cancel)
            return
        }
        
        guard let host = url.host else {
            decisionHandler(.cancel)
            return
        }
        
        // On iOS < 11 block ads the old way. On >= 11, use WKContentRuleListStore (already loaded)
        if #available(iOS 11, *) {} else {
            AdBlocker.shared.shouldBlock(host: host) ? decisionHandler(.cancel) : decisionHandler(.allow)
            return
        }
        
        // DEBUG
        //if !BlockAds.shared.shouldBlock(host: host) {
        //    debugLog("HOST: \(host)")
        //}
        
        decisionHandler(.allow)
    }
}