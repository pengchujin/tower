import XCTest
@testable import Tower

final class LocalizationTests: XCTestCase {
    private let supportedLocales = [
        "ar", "de", "en", "es", "fr", "id", "ja", "ko", "pt-BR", "ru",
        "th", "tr", "vi", "zh-Hans", "zh-Hant",
    ]

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testCatalogContainsEverySupportedLocaleForEveryString() throws {
        let catalog = try loadCatalog(named: "Localizable")
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])

        XCTAssertGreaterThanOrEqual(strings.count, 400)
        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any], key)
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                key
            )
            XCTAssertEqual(
                Set(localizations.keys),
                Set(supportedLocales),
                "Missing translation for \(key)"
            )
        }
    }

    func testInfoPlistPrivacyPromptsAreLocalized() throws {
        let catalog = try loadCatalog(named: "InfoPlist")
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])

        for key in [
            "CFBundleDisplayName",
            "NSCameraUsageDescription",
            "NSLocalNetworkUsageDescription",
        ] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(Set(localizations.keys), Set(supportedLocales))
        }
    }

    func testRepresentativeNavigationLabelsAreHumanReviewed() throws {
        let catalog = try loadCatalog(named: "Localizable")

        XCTAssertEqual(try value(for: "订阅", locale: "en", in: catalog), "Subscriptions")
        XCTAssertEqual(try value(for: "导出", locale: "ja", in: catalog), "エクスポート")
        XCTAssertEqual(try value(for: "设置", locale: "ko", in: catalog), "설정")
        XCTAssertEqual(try value(for: "我的订阅", locale: "zh-Hant", in: catalog), "我的訂閱")
        XCTAssertEqual(try value(for: "塔台", locale: "en", in: catalog), "Tower")
        XCTAssertEqual(try value(for: "塔台", locale: "zh-Hans", in: catalog), "塔台")
        XCTAssertEqual(
            try value(for: "默认保持原始订阅", locale: "en", in: catalog),
            "Original subscription by default"
        )
        XCTAssertEqual(try value(for: "上移", locale: "en", in: catalog), "Move Up")
        XCTAssertEqual(try value(for: "下移", locale: "en", in: catalog), "Move Down")
        XCTAssertEqual(
            try value(for: "%@ 已过期 %lld 天", locale: "en", in: catalog),
            "%1$@ expired %2$lld days ago"
        )
    }

    func testPrimaryExportLabelsAreConciseAndHumanReviewed() throws {
        let catalog = try loadCatalog(named: "Localizable")
        let expected: [String: [String]] = [
            "ar": ["التطبيق الهدف", "تصفية البروتوكولات", "تصدير إلى %@", "اضغط مطولاً لإعادة الترتيب", "لـ %@ فقط", "تصدير ملف إلى %@", "جاهز للتصدير"],
            "de": ["Ziel-App", "Protokollfilter", "In %@ exportieren", "Zum Neuanordnen gedrückt halten", "Nur für %@", "Datei in %@ exportieren", "Bereit zum Exportieren"],
            "en": ["Target App", "Protocol Filter", "Export to %@", "Touch and Hold to Reorder", "For %@ only", "Export File to %@", "Ready to Export"],
            "es": ["App de destino", "Filtro de protocolos", "Exportar a %@", "Mantén pulsado para reordenar", "Solo para %@", "Exportar archivo a %@", "Listo para exportar"],
            "fr": ["App cible", "Filtre de protocoles", "Exporter vers %@", "Maintenez le doigt pour réorganiser", "Pour %@ uniquement", "Exporter un fichier vers %@", "Prêt à exporter"],
            "id": ["Aplikasi tujuan", "Filter protokol", "Ekspor ke %@", "Tekan lama untuk mengurutkan ulang", "Hanya untuk %@", "Ekspor file ke %@", "Siap diekspor"],
            "ja": ["対象アプリ", "プロトコルフィルタ", "%@にエクスポート", "長押しして並べ替え", "%@ のみ", "%@にファイルをエクスポート", "エクスポートの準備完了"],
            "ko": ["대상 앱", "프로토콜 필터", "%@로 내보내기", "길게 눌러 순서 변경", "%@에만 적용", "%@로 파일 내보내기", "내보낼 준비 완료"],
            "pt-BR": ["App de destino", "Filtro de protocolos", "Exportar para %@", "Mantenha pressionado para reordenar", "Somente para %@", "Exportar arquivo para %@", "Pronto para exportar"],
            "ru": ["Целевое приложение", "Фильтр протоколов", "Экспортировать в %@", "Удерживайте для изменения порядка", "Только для %@", "Экспортировать файл в %@", "Готово к экспорту"],
            "th": ["แอปเป้าหมาย", "ตัวกรองโปรโตคอล", "ส่งออกไปยัง %@", "แตะค้างไว้เพื่อจัดลำดับใหม่", "สำหรับ %@ เท่านั้น", "ส่งออกไฟล์ไปยัง %@", "พร้อมส่งออก"],
            "tr": ["Hedef Uygulama", "Protokol Filtresi", "%@ Uygulamasına Dışa Aktar", "Yeniden sıralamak için basılı tutun", "Yalnızca %@ için", "Dosyayı %@ Uygulamasına Dışa Aktar", "Dışa Aktarmaya Hazır"],
            "vi": ["Ứng dụng đích", "Bộ lọc giao thức", "Xuất sang %@", "Chạm và giữ để sắp xếp lại", "Chỉ áp dụng cho %@", "Xuất tệp sang %@", "Sẵn sàng xuất"],
            "zh-Hans": ["目标客户端", "协议筛选", "一键导出到 %@", "长按拖动排序", "只影响 %@", "用文件导出到 %@", "转换已就绪"],
            "zh-Hant": ["目標客戶端", "協定篩選", "一鍵匯出到 %@", "按住以重新排序", "僅影響 %@", "用檔案匯出到 %@", "轉換已就緒"],
        ]

        for locale in supportedLocales {
            let translations = try XCTUnwrap(expected[locale])
            XCTAssertEqual(try value(for: "目标客户端", locale: locale, in: catalog), translations[0])
            XCTAssertEqual(try value(for: "协议筛选", locale: locale, in: catalog), translations[1])
            XCTAssertEqual(try value(for: "一键导出到 %@", locale: locale, in: catalog), translations[2])
            XCTAssertEqual(try value(for: "长按拖动排序", locale: locale, in: catalog), translations[3])
            XCTAssertEqual(try value(for: "只影响 %@", locale: locale, in: catalog), translations[4])
            XCTAssertEqual(try value(for: "用文件导出到 %@", locale: locale, in: catalog), translations[5])
            XCTAssertEqual(try value(for: "转换已就绪", locale: locale, in: catalog), translations[6])
        }
    }

    func testEnglishExportExplanationsAreNaturalAndSpecific() throws {
        let catalog = try loadCatalog(named: "Localizable")
        let expected = [
            "关掉的协议不会写进 %@ 的配置，并计入“已跳过”。其他客户端不受影响。":
                "Disabled protocols are excluded from the %@ profile and counted as skipped. Other apps are unaffected.",
            "目标客户端不支持、或您在协议筛选里关掉的节点不会写入配置，原节点仍保留在塔台中。":
                "Unsupported or disabled nodes are omitted from this profile but remain in Tower.",
            "塔台会通过 %@ 的 URL Scheme 打开客户端。配置只在这台 iPhone 的 127.0.0.1 临时地址保留 45 秒，不会上传；需要更新时回到塔台再次导入。":
                "Tower opens %@ using its URL scheme. The profile stays on this iPhone at 127.0.0.1 for 45 seconds and is never uploaded. Return to Tower to import updates.",
            "Quantumult X 目前没有公开完整配置导入的 URL Scheme。点击下方按钮会立即打开系统文件分享，不上传您的订阅，也不会用不完整的远程资源替代本地规则。":
                "Quantumult X does not offer a URL scheme for full profiles. The button opens the iOS share sheet. Tower never uploads your subscription or replaces local rules with incomplete remote ones.",
            "本机一键导出": "Local Export",
            "使用本地文件导出": "File Export",
        ]

        for (key, translation) in expected {
            XCTAssertEqual(try value(for: key, locale: "en", in: catalog), translation)
        }
    }

    func testEnglishTechnicalTermsUseAppAndProtocolVocabulary() throws {
        let catalog = try loadCatalog(named: "Localizable")
        let expected = [
            "协议": "Protocol",
            "等待有效的订阅链接或节点协议": "Waiting for a valid subscription URL or node protocol",
            "粘贴订阅链接或节点协议": "Paste a subscription URL or node protocol",
            "请填写该协议需要的密码或 UUID": "Enter the password or UUID required by this protocol",
            "混淆": "Obfuscation",
            "认证": "Authentication",
            "认证信息": "Authentication Details",
            "订阅节点": "Subscription Nodes",
            "取消勾选的节点仍保存在塔台中，但不会写入任何客户端配置。":
                "Unchecked nodes remain in Tower but are excluded from every exported profile.",
        ]

        for (key, translation) in expected {
            XCTAssertEqual(try value(for: key, locale: "en", in: catalog), translation)
        }
    }

    func testTechnicalGlossaryIsNotTranslatedAsEverydayLanguage() throws {
        let catalog = try loadCatalog(named: "Localizable")
        let expected: [String: [String]] = [
            "ar": ["البروتوكول", "التمويه", "المصادقة", "تفاصيل المصادقة", "عُقد الاشتراك"],
            "de": ["Protokoll", "Verschleierung", "Authentifizierung", "Authentifizierungsdetails", "Abonnement-Knoten"],
            "en": ["Protocol", "Obfuscation", "Authentication", "Authentication Details", "Subscription Nodes"],
            "es": ["Protocolo", "Ofuscación", "Autenticación", "Datos de autenticación", "Nodos de suscripción"],
            "fr": ["Protocole", "Obfuscation", "Authentification", "Détails d’authentification", "Nœuds d’abonnement"],
            "id": ["Protokol", "Obfuscation", "Autentikasi", "Detail autentikasi", "Node langganan"],
            "ja": ["プロトコル", "難読化", "認証", "認証情報", "サブスクリプションノード"],
            "ko": ["프로토콜", "난독화", "인증", "인증 정보", "구독 노드"],
            "pt-BR": ["Protocolo", "Ofuscação", "Autenticação", "Dados de autenticação", "Nós da assinatura"],
            "ru": ["Протокол", "Обфускация", "Аутентификация", "Данные аутентификации", "Узлы подписки"],
            "th": ["โปรโตคอล", "การอำพราง", "การยืนยันตัวตน", "รายละเอียดการยืนยันตัวตน", "โหนดการสมัครสมาชิก"],
            "tr": ["Protokol", "Gizleme", "Kimlik Doğrulama", "Kimlik Doğrulama Bilgileri", "Abonelik Düğümleri"],
            "vi": ["Giao thức", "Làm rối", "Xác thực", "Thông tin xác thực", "Nút đăng ký"],
            "zh-Hans": ["协议", "混淆", "认证", "认证信息", "订阅节点"],
            "zh-Hant": ["協定", "混淆", "認證", "認證資訊", "訂閱節點"],
        ]

        for locale in supportedLocales {
            let translations = try XCTUnwrap(expected[locale])
            XCTAssertEqual(try value(for: "协议", locale: locale, in: catalog), translations[0])
            XCTAssertEqual(try value(for: "混淆", locale: locale, in: catalog), translations[1])
            XCTAssertEqual(try value(for: "认证", locale: locale, in: catalog), translations[2])
            XCTAssertEqual(try value(for: "认证信息", locale: locale, in: catalog), translations[3])
            XCTAssertEqual(try value(for: "订阅节点", locale: locale, in: catalog), translations[4])
        }
    }

    func testProxyProviderIsNotTranslatedAsAnAirport() throws {
        let catalog = try loadCatalog(named: "Localizable")
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let bannedTerms: [String: [String]] = [
            "ar": ["مطار"],
            "de": ["Flughafen"],
            "en": ["airport"],
            "es": ["aeropuerto"],
            "fr": ["aéroport"],
            "id": ["bandara"],
            "ja": ["空港"],
            "ko": ["공항"],
            "pt-BR": ["aeroporto"],
            "ru": ["аэропорт"],
            "th": ["สนามบิน"],
            "tr": ["havaalan", "havaliman"],
            "vi": ["sân bay"],
        ]

        for key in strings.keys where key.contains("机场") {
            for (locale, terms) in bannedTerms {
                let translation = try value(for: key, locale: locale, in: catalog)
                for term in terms {
                    XCTAssertFalse(
                        translation.localizedCaseInsensitiveContains(term),
                        "\(locale) translated proxy provider as a physical airport: \(key)"
                    )
                }
            }
        }
    }

    func testPrimarySubscriptionTabIsALocalizedNoun() throws {
        let catalog = try loadCatalog(named: "Localizable")
        let expected = [
            "ar": "الاشتراكات",
            "de": "Abonnements",
            "en": "Subscriptions",
            "es": "Suscripciones",
            "fr": "Abonnements",
            "id": "Langganan",
            "ja": "サブスクリプション",
            "ko": "구독",
            "pt-BR": "Assinaturas",
            "ru": "Подписки",
            "th": "การสมัครสมาชิก",
            "tr": "Abonelikler",
            "vi": "Gói đăng ký",
            "zh-Hans": "订阅",
            "zh-Hant": "訂閱",
        ]

        for (locale, translation) in expected {
            XCTAssertEqual(try value(for: "订阅", locale: locale, in: catalog), translation)
        }
    }

    func testRegionNamesFollowTheSelectedAppLocale() {
        XCTAssertEqual(
            AppLocalization.regionName(for: "JP", locale: Locale(identifier: "en")),
            "Japan"
        )
        XCTAssertEqual(
            AppLocalization.regionName(for: "JP", locale: Locale(identifier: "ja")),
            "日本"
        )
    }

    private func loadCatalog(named name: String) throws -> [String: Any] {
        let url = repositoryRoot
            .appendingPathComponent("Tower")
            .appendingPathComponent("\(name).xcstrings")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private func value(
        for key: String,
        locale: String,
        in catalog: [String: Any]
    ) throws -> String {
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings[key] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let localization = try XCTUnwrap(localizations[locale] as? [String: Any])
        let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
        return try XCTUnwrap(unit["value"] as? String)
    }
}
