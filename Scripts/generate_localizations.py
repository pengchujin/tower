#!/usr/bin/env python3
"""Generate Tower string catalogs from Xcode's extracted source catalog.

The script is intentionally a maintainer tool, not an app runtime dependency.
It protects printf placeholders, translates in batches, and emits deterministic
Xcode string catalogs that are bundled with the application for offline use.
"""

from __future__ import annotations

import argparse
import json
import re
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


TRANSLATION_ENDPOINT = "https://translate.googleapis.com/translate_a/single"
SEPARATOR = "[[[019FBDCD859777A29936E0586CC004D0]]]"
PLACEHOLDER_PATTERN = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@)")

LANGUAGES = {
    "en": "en",
    "zh-Hant": "zh-TW",
    "ja": "ja",
    "ko": "ko",
    "es": "es",
    "fr": "fr",
    "de": "de",
    "pt-BR": "pt",
    "ru": "ru",
    "ar": "ar",
    "tr": "tr",
    "id": "id",
    "th": "th",
    "vi": "vi",
}

DYNAMIC_STRINGS = (
    "集中管理代理订阅和自建节点，再转换成常用客户端配置。",
    "ACL4SSR 默认",
    "去广告、自动测速，含国外媒体、电报、微软和苹果分流。",
    "ACL4SSR 全分组",
    "最完整的分组：流媒体、AI、游戏、音乐，并按节点名分出地区组。",
    "ACL4SSR 精简",
    "只保留节点选择、自动选择、直连与拦截，策略组最少。",
    "节点与配置",
    "默认保持原始订阅",
    "节点附加订阅名称",
    "节点名后显示来源，便于区分多个订阅服务。",
    "过滤订阅节点信息",
    "开启后隐藏流量、到期、官网和客服等信息节点。",
    "优先使用规则集",
    "兼容时引用远程规则集，不兼容的客户端会自动保留本地规则。",
    "配置名称",
    "恢复默认",
    "导出的文件、本机导入和客户端订阅会使用同一个名称。",
    "%@ 到期还剩 1 天",
    "订阅到期还剩 1 天，请及时续费。",
    "%@ 到期还剩 %lld 天",
    "到期日期：%@",
    "提醒时间：%@",
    "导入内容",
    "仅节点",
    "只添加节点订阅，不替换客户端现有的规则和策略组。",
    "导入节点、规则和策略组组成的完整配置。",
    "仅节点 · %@",
    "塔台只会把节点订阅交给 %@，不会替换客户端现有的规则和策略组。订阅保留在这台 iPhone 的临时地址，不会上传。",
    "仅导入节点到 %@",
)

DISPLAY_NAMES = {
    "zh-Hans": "塔台",
    "zh-Hant": "塔台",
    "en": "Tower",
    "ja": "Tower",
    "ko": "Tower",
    "es": "Tower",
    "fr": "Tower",
    "de": "Tower",
    "pt-BR": "Tower",
    "ru": "Tower",
    "ar": "Tower",
    "tr": "Tower",
    "id": "Tower",
    "th": "Tower",
    "vi": "Tower",
}

DEPRECATED_KEYS = {
    "节点名后显示来源，便于区分多个机场。",
    "集中管理机场订阅和自建节点，再转换成常用客户端配置。",
}

# Keep the app name and the most prominent navigation labels consistent. The
# remaining catalog is generated in full and can be polished in Xcode later.
CORE_OVERRIDES = {
    "en": {
        "塔台": "Tower",
        "订阅": "Subscriptions",
        "规则": "Rules",
        "导入": "Import",
        "设置": "Settings",
        "我的订阅": "My Subscriptions",
        "准备你的节点": "Prepare Your Nodes",
        "集中管理代理订阅和自建节点，再转换成常用客户端配置。": "Manage proxy subscriptions and self-hosted nodes in one place, then convert them into configurations for popular clients.",
        "分流规则": "Routing Rules",
        "生成与导入": "Generate & Import",
        "粘贴识别": "Paste & Detect",
        "扫码": "Scan",
        "手动添加": "Manual",
        "保存": "Save",
        "取消": "Cancel",
        "添加": "Add",
        "完成": "Done",
        "全屏预览": "Full-screen Preview",
        "测速": "Test Latency",
        "续费提醒": "Renewal Reminders",
        "局域网订阅": "Local Network Subscription",
        "自动选择": "Auto Select",
        "手动选择": "Manual Select",
        "直连": "Direct",
        "拒绝": "Reject",
        "不可达": "Unreachable",
        "已启用": "Enabled",
        "节点": "Nodes",
        "地区": "Regions",
        "自有节点": "Own Nodes",
        "节点与配置": "Nodes & Profiles",
        "默认保持原始订阅": "Original subscription by default",
        "节点附加订阅名称": "Append Subscription Name",
        "节点名后显示来源，便于区分多个订阅服务。": "Show the subscription source after each node name.",
        "过滤订阅节点信息": "Filter Subscription Info",
        "开启后隐藏流量、到期、官网和客服等信息节点。": "Hide quota, expiry, website, and support entries when enabled.",
        "优先使用规则集": "Prefer Rule Sets",
        "兼容时引用远程规则集，不兼容的客户端会自动保留本地规则。": "Reference remote rule sets when compatible; incompatible clients automatically keep local rules.",
        "配置名称": "Profile Name",
        "恢复默认": "Reset",
        "导出的文件、本机导入和客户端订阅会使用同一个名称。": "Exports, local imports, and client subscriptions use this name.",
        "仅节点": "Nodes Only",
        "导入内容": "Import Content",
        "只添加节点订阅，不替换客户端现有的规则和策略组。": "Add a node subscription without replacing existing rules or policy groups.",
        "导入节点、规则和策略组组成的完整配置。": "Import a complete profile with nodes, rules, and policy groups.",
        "仅节点 · %@": "Nodes Only · %@",
        "仅导入节点到 %@": "Import Nodes to %@",
        "%@ 到期还剩 %lld 天": "%@ expires in %lld days",
        "%@ 到期还剩 1 天": "%@ expires in 1 day",
        "订阅到期还剩 1 天，请及时续费。": "This subscription expires in 1 day. Renew it soon.",
    },
    "zh-Hant": {
        "塔台": "塔台",
        "订阅": "訂閱",
        "规则": "規則",
        "导入": "匯入",
        "设置": "設定",
        "我的订阅": "我的訂閱",
        "分流规则": "分流規則",
        "生成与导入": "產生與匯入",
        "粘贴识别": "貼上識別",
        "扫码": "掃描",
        "手动添加": "手動新增",
        "保存": "儲存",
        "取消": "取消",
        "添加": "新增",
        "完成": "完成",
        "全屏预览": "全螢幕預覽",
        "测速": "延遲測試",
        "续费提醒": "續費提醒",
        "局域网订阅": "區域網路訂閱",
        "自动选择": "自動選擇",
        "手动选择": "手動選擇",
        "直连": "直接連線",
        "拒绝": "拒絕",
        "不可达": "無法連線",
        "已启用": "已啟用",
        "节点": "節點",
        "地区": "地區",
        "自有节点": "自有節點",
        "优先使用规则集": "優先使用規則集",
        "兼容时引用远程规则集，不兼容的客户端会自动保留本地规则。": "相容時引用遠端規則集，不相容的客戶端會自動保留本機規則。",
    },
    "ja": {
        "塔台": "Tower",
        "订阅": "サブスクリプション",
        "规则": "ルール",
        "导入": "インポート",
        "设置": "設定",
        "我的订阅": "マイサブスクリプション",
        "准备你的节点": "ノードを準備",
        "集中管理代理订阅和自建节点，再转换成常用客户端配置。": "プロキシサブスクリプションと自分のノードをまとめて管理し、主要クライアント向けの構成に変換します。",
        "分流规则": "ルーティングルール",
        "生成与导入": "生成とインポート",
        "粘贴识别": "貼り付け",
        "扫码": "スキャン",
        "手动添加": "手動追加",
        "保存": "保存",
        "取消": "キャンセル",
        "添加": "追加",
        "完成": "完了",
        "全屏预览": "全画面プレビュー",
        "测速": "遅延テスト",
        "续费提醒": "更新リマインダー",
        "局域网订阅": "ローカルネットワーク共有",
        "自动选择": "自動選択",
        "手动选择": "手動選択",
        "直连": "直接接続",
        "拒绝": "拒否",
        "不可达": "到達不能",
        "已启用": "有効",
        "节点": "ノード",
        "地区": "エリア",
        "自有节点": "自分のノード",
    },
    "ko": {
        "塔台": "Tower",
        "订阅": "구독",
        "规则": "규칙",
        "导入": "가져오기",
        "设置": "설정",
        "我的订阅": "내 구독",
        "分流规则": "라우팅 규칙",
        "生成与导入": "생성 및 가져오기",
        "粘贴识别": "붙여넣기",
        "扫码": "스캔",
        "手动添加": "직접 추가",
        "保存": "저장",
        "取消": "취소",
        "添加": "추가",
        "完成": "완료",
        "全屏预览": "전체 화면 미리보기",
        "测速": "지연 시간 테스트",
        "续费提醒": "갱신 알림",
        "局域网订阅": "로컬 네트워크 구독",
        "自动选择": "자동 선택",
        "手动选择": "수동 선택",
        "直连": "직접 연결",
        "拒绝": "차단",
        "不可达": "연결 불가",
        "已启用": "활성",
        "节点": "노드",
        "地区": "지역",
        "自有节点": "개인 노드",
    },
    "es": {
        "塔台": "Tower",
        "订阅": "Suscripciones",
        "规则": "Reglas",
        "导入": "Importar",
        "设置": "Ajustes",
        "我的订阅": "Mis suscripciones",
        "分流规则": "Reglas de enrutamiento",
        "生成与导入": "Generar e importar",
        "完成": "Listo",
        "测速": "Probar latencia",
        "已启用": "Activas",
        "节点": "Nodos",
        "地区": "Regiones",
        "自有节点": "Nodos propios",
    },
    "fr": {
        "塔台": "Tower",
        "订阅": "Abonnements",
        "规则": "Règles",
        "导入": "Importer",
        "设置": "Réglages",
        "我的订阅": "Mes abonnements",
        "分流规则": "Règles de routage",
        "生成与导入": "Générer et importer",
        "完成": "Terminé",
        "测速": "Tester la latence",
        "已启用": "Actifs",
        "节点": "Nœuds",
        "地区": "Régions",
        "自有节点": "Nœuds personnels",
    },
    "de": {
        "塔台": "Tower",
        "订阅": "Abonnements",
        "规则": "Regeln",
        "导入": "Import",
        "设置": "Einstellungen",
        "我的订阅": "Meine Abonnements",
        "分流规则": "Routing-Regeln",
        "生成与导入": "Erstellen & importieren",
        "完成": "Fertig",
        "测速": "Latenz testen",
        "已启用": "Aktiv",
        "节点": "Knoten",
        "地区": "Regionen",
        "自有节点": "Eigene Knoten",
    },
    "pt-BR": {
        "塔台": "Tower",
        "订阅": "Assinaturas",
        "规则": "Regras",
        "导入": "Importar",
        "设置": "Ajustes",
        "我的订阅": "Minhas assinaturas",
        "分流规则": "Regras de roteamento",
        "生成与导入": "Gerar e importar",
        "完成": "Concluído",
        "测速": "Testar latência",
        "已启用": "Ativas",
        "节点": "Nós",
        "地区": "Regiões",
        "自有节点": "Nós próprios",
    },
    "ru": {
        "塔台": "Tower",
        "订阅": "Подписки",
        "规则": "Правила",
        "导入": "Импорт",
        "设置": "Настройки",
        "我的订阅": "Мои подписки",
        "分流规则": "Правила маршрутизации",
        "生成与导入": "Создание и импорт",
        "完成": "Готово",
        "测速": "Проверить задержку",
        "已启用": "Активные",
        "节点": "Узлы",
        "地区": "Регионы",
        "自有节点": "Свои узлы",
    },
    "ar": {
        "塔台": "Tower",
        "订阅": "الاشتراكات",
        "规则": "القواعد",
        "导入": "استيراد",
        "设置": "الإعدادات",
        "我的订阅": "اشتراكاتي",
        "分流规则": "قواعد التوجيه",
        "生成与导入": "إنشاء واستيراد",
        "完成": "تم",
        "测速": "اختبار زمن الاستجابة",
        "已启用": "مفعّلة",
        "节点": "العُقد",
        "地区": "المناطق",
        "自有节点": "عُقدي",
    },
    "tr": {
        "塔台": "Tower",
        "订阅": "Abonelikler",
        "规则": "Kurallar",
        "导入": "İçe Aktar",
        "设置": "Ayarlar",
        "我的订阅": "Aboneliklerim",
        "分流规则": "Yönlendirme Kuralları",
        "生成与导入": "Oluştur ve İçe Aktar",
        "完成": "Bitti",
        "测速": "Gecikmeyi Test Et",
        "已启用": "Etkin",
        "节点": "Düğümler",
        "地区": "Bölgeler",
        "自有节点": "Kendi Düğümlerim",
    },
    "id": {
        "塔台": "Tower",
        "订阅": "Langganan",
        "规则": "Aturan",
        "导入": "Impor",
        "设置": "Pengaturan",
        "我的订阅": "Langganan Saya",
        "分流规则": "Aturan Perutean",
        "生成与导入": "Buat & Impor",
        "完成": "Selesai",
        "测速": "Uji Latensi",
        "已启用": "Aktif",
        "节点": "Node",
        "地区": "Wilayah",
        "自有节点": "Node Pribadi",
    },
    "th": {
        "塔台": "Tower",
        "订阅": "การสมัครสมาชิก",
        "规则": "กฎ",
        "导入": "นำเข้า",
        "设置": "การตั้งค่า",
        "我的订阅": "การสมัครของฉัน",
        "分流规则": "กฎการกำหนดเส้นทาง",
        "生成与导入": "สร้างและนำเข้า",
        "完成": "เสร็จสิ้น",
        "测速": "ทดสอบเวลาแฝง",
        "已启用": "เปิดใช้",
        "节点": "โหนด",
        "地区": "ภูมิภาค",
        "自有节点": "โหนดส่วนตัว",
    },
    "vi": {
        "塔台": "Tower",
        "订阅": "Gói đăng ký",
        "规则": "Quy tắc",
        "导入": "Nhập",
        "设置": "Cài đặt",
        "我的订阅": "Gói đăng ký của tôi",
        "分流规则": "Quy tắc định tuyến",
        "生成与导入": "Tạo & Nhập",
        "完成": "Xong",
        "测速": "Kiểm tra độ trễ",
        "已启用": "Đang bật",
        "节点": "Nút",
        "地区": "Khu vực",
        "自有节点": "Nút riêng",
    },
}

INFO_PLIST_SOURCE = {
    "CFBundleDisplayName": "塔台",
    "NSCameraUsageDescription": "用于扫描订阅或节点二维码。",
    "NSLocalNetworkUsageDescription": "用于在同一 Wi-Fi 中向你的电脑或路由器共享转换后的订阅配置。",
}

INFO_PLIST_TRANSLATIONS = {
    "en": {
        "NSCameraUsageDescription": "Scan subscription or node QR codes.",
        "NSLocalNetworkUsageDescription": "Share converted subscription configurations with your computer or router on the same Wi-Fi.",
    },
    "zh-Hant": {
        "NSCameraUsageDescription": "用於掃描訂閱或節點 QR Code。",
        "NSLocalNetworkUsageDescription": "用於在同一 Wi-Fi 中向你的電腦或路由器分享轉換後的訂閱設定。",
    },
    "ja": {
        "NSCameraUsageDescription": "サブスクリプションまたはノードのQRコードをスキャンするために使用します。",
        "NSLocalNetworkUsageDescription": "同じWi-Fi上のコンピュータまたはルーターと変換済みサブスクリプション構成を共有するために使用します。",
    },
    "ko": {
        "NSCameraUsageDescription": "구독 또는 노드 QR 코드를 스캔하는 데 사용됩니다.",
        "NSLocalNetworkUsageDescription": "동일한 Wi-Fi의 컴퓨터 또는 라우터와 변환된 구독 구성을 공유하는 데 사용됩니다.",
    },
    "es": {
        "NSCameraUsageDescription": "Se usa para escanear códigos QR de suscripciones o nodos.",
        "NSLocalNetworkUsageDescription": "Se usa para compartir configuraciones de suscripción convertidas con tu ordenador o router en la misma red Wi-Fi.",
    },
    "fr": {
        "NSCameraUsageDescription": "Utilisé pour scanner les codes QR d’abonnements ou de nœuds.",
        "NSLocalNetworkUsageDescription": "Utilisé pour partager les configurations d’abonnement converties avec votre ordinateur ou routeur sur le même réseau Wi-Fi.",
    },
    "de": {
        "NSCameraUsageDescription": "Zum Scannen von QR-Codes für Abonnements oder Knoten.",
        "NSLocalNetworkUsageDescription": "Zum Teilen konvertierter Abonnementkonfigurationen mit deinem Computer oder Router im selben WLAN.",
    },
    "pt-BR": {
        "NSCameraUsageDescription": "Usado para ler códigos QR de assinaturas ou nós.",
        "NSLocalNetworkUsageDescription": "Usado para compartilhar configurações de assinatura convertidas com seu computador ou roteador na mesma rede Wi-Fi.",
    },
    "ru": {
        "NSCameraUsageDescription": "Используется для сканирования QR-кодов подписок или узлов.",
        "NSLocalNetworkUsageDescription": "Используется для передачи преобразованных конфигураций подписок компьютеру или маршрутизатору в той же сети Wi-Fi.",
    },
    "ar": {
        "NSCameraUsageDescription": "يُستخدم لمسح رموز QR للاشتراكات أو العُقد.",
        "NSLocalNetworkUsageDescription": "يُستخدم لمشاركة إعدادات الاشتراك المحوّلة مع الكمبيوتر أو جهاز التوجيه على شبكة Wi-Fi نفسها.",
    },
    "tr": {
        "NSCameraUsageDescription": "Abonelik veya düğüm QR kodlarını taramak için kullanılır.",
        "NSLocalNetworkUsageDescription": "Dönüştürülen abonelik yapılandırmalarını aynı Wi-Fi ağındaki bilgisayarınızla veya yönlendiricinizle paylaşmak için kullanılır.",
    },
    "id": {
        "NSCameraUsageDescription": "Digunakan untuk memindai kode QR langganan atau node.",
        "NSLocalNetworkUsageDescription": "Digunakan untuk membagikan konfigurasi langganan yang dikonversi ke komputer atau router di Wi-Fi yang sama.",
    },
    "th": {
        "NSCameraUsageDescription": "ใช้เพื่อสแกนคิวอาร์โค้ดการสมัครสมาชิกหรือโหนด",
        "NSLocalNetworkUsageDescription": "ใช้เพื่อแชร์การกำหนดค่าการสมัครสมาชิกที่แปลงแล้วกับคอมพิวเตอร์หรือเราเตอร์บน Wi-Fi เดียวกัน",
    },
    "vi": {
        "NSCameraUsageDescription": "Dùng để quét mã QR của gói đăng ký hoặc nút.",
        "NSLocalNetworkUsageDescription": "Dùng để chia sẻ cấu hình đăng ký đã chuyển đổi với máy tính hoặc bộ định tuyến trên cùng mạng Wi-Fi.",
    },
}


def protect_placeholders(text: str) -> tuple[str, dict[str, str]]:
    replacements: dict[str, str] = {}

    def replace(match: re.Match[str]) -> str:
        # Private-looking numeric markers survive machine translation much more
        # reliably than tokens containing words such as "PLACEHOLDER".
        token = f"⟦019F{len(replacements):04X}⟧"
        replacements[token] = match.group(0)
        return token

    return PLACEHOLDER_PATTERN.sub(replace, text), replacements


def restore_placeholders(text: str, replacements: dict[str, str]) -> str:
    for token, value in replacements.items():
        text = text.replace(token, value)
    return text


def request_translation(text: str, target: str) -> str:
    payload = urllib.parse.urlencode(
        {"client": "gtx", "sl": "zh-CN", "tl": target, "dt": "t", "q": text}
    ).encode("utf-8")
    request = urllib.request.Request(
        TRANSLATION_ENDPOINT,
        data=payload,
        headers={"User-Agent": "TowerLocalizationMaintainer/1.0"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        body = json.load(response)
    return "".join(segment[0] for segment in body[0] if segment[0])


def chunks(items: list[str], max_characters: int = 4_500) -> list[list[str]]:
    result: list[list[str]] = []
    current: list[str] = []
    current_length = 0
    for item in items:
        added = len(item) + len(SEPARATOR) + 2
        if current and current_length + added > max_characters:
            result.append(current)
            current = []
            current_length = 0
        current.append(item)
        current_length += added
    if current:
        result.append(current)
    return result


def translate_batch(values: list[str], target: str) -> list[str]:
    protected_values: list[str] = []
    placeholder_maps: list[dict[str, str]] = []
    for value in values:
        protected, replacements = protect_placeholders(value)
        protected_values.append(protected)
        placeholder_maps.append(replacements)

    joined = f"\n{SEPARATOR}\n".join(protected_values)
    for attempt in range(4):
        try:
            translated = request_translation(joined, target)
            pieces = re.split(rf"\s*{re.escape(SEPARATOR)}\s*", translated)
            if len(pieces) != len(values):
                raise ValueError(
                    f"separator mismatch: expected {len(values)}, received {len(pieces)}"
                )
            return [
                restore_placeholders(piece.strip(), replacements)
                for piece, replacements in zip(pieces, placeholder_maps)
            ]
        except Exception:
            if attempt == 3:
                raise
            time.sleep(1.5 * (attempt + 1))
    raise AssertionError("unreachable")


def translate_language(locale: str, target: str, values: list[str]) -> tuple[str, list[str]]:
    translated: list[str] = []
    for batch in chunks(values):
        translated.extend(translate_batch(batch, target))
    return locale, translated


def string_unit(value: str) -> dict[str, object]:
    return {"stringUnit": {"state": "translated", "value": value}}


def build_catalog(source_catalog: Path, output: Path) -> dict[str, dict[str, str]]:
    document = json.loads(source_catalog.read_text(encoding="utf-8"))
    for key in DEPRECATED_KEYS:
        document.setdefault("strings", {}).pop(key, None)
    existing_document = (
        json.loads(output.read_text(encoding="utf-8")) if output.exists() else None
    )
    for value in DYNAMIC_STRINGS:
        document.setdefault("strings", {}).setdefault(value, {})

    keys = sorted(document["strings"])
    source_values: list[str] = []
    for key in keys:
        source_value = (
            document["strings"][key]
            .get("localizations", {})
            .get("zh-Hans", {})
            .get("stringUnit", {})
            .get("value", key)
        )
        source_values.append(source_value)

    lookup: dict[str, dict[str, str]] = {"zh-Hans": dict(zip(keys, source_values))}
    missing_by_locale: dict[str, list[tuple[str, str]]] = {}
    for locale in LANGUAGES:
        lookup[locale] = {}
        missing_by_locale[locale] = []
        for key, source_value in zip(keys, source_values):
            existing_entry = (
                existing_document.get("strings", {}).get(key, {})
                if existing_document
                else {}
            )
            existing_source = (
                existing_entry.get("localizations", {})
                .get("zh-Hans", {})
                .get("stringUnit", {})
                .get("value")
            )
            existing_translation = (
                existing_entry.get("localizations", {})
                .get(locale, {})
                .get("stringUnit", {})
                .get("value")
            )
            if existing_source == source_value and existing_translation:
                lookup[locale][key] = existing_translation
            else:
                missing_by_locale[locale].append((key, source_value))

    translated_by_locale: dict[str, list[str]] = {}
    with ThreadPoolExecutor(max_workers=4) as executor:
        futures = {
            executor.submit(
                translate_language,
                locale,
                target,
                [value for _, value in missing_by_locale[locale]],
            ): locale
            for locale, target in LANGUAGES.items()
            if missing_by_locale[locale]
        }
        for future in as_completed(futures):
            locale, translated = future.result()
            translated_by_locale[locale] = translated
            print(f"translated {locale}: {len(translated)} new strings", flush=True)

    for locale in LANGUAGES:
        for (key, _), translated in zip(
            missing_by_locale[locale], translated_by_locale.get(locale, [])
        ):
            lookup[locale][key] = translated
        lookup[locale].update(CORE_OVERRIDES.get(locale, {}))

    for index, key in enumerate(keys):
        entry = document["strings"][key]
        localizations = entry.setdefault("localizations", {})
        localizations["zh-Hans"] = string_unit(source_values[index])
        for locale in LANGUAGES:
            localizations[locale] = string_unit(lookup[locale][key])

    document["sourceLanguage"] = "zh-Hans"
    document["version"] = "1.0"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return lookup


def build_info_catalog(output: Path) -> None:
    strings: dict[str, object] = {}
    for plist_key, source_value in INFO_PLIST_SOURCE.items():
        localizations = {"zh-Hans": string_unit(source_value)}
        for locale in LANGUAGES:
            if plist_key == "CFBundleDisplayName":
                localized_value = DISPLAY_NAMES[locale]
            else:
                localized_value = INFO_PLIST_TRANSLATIONS[locale][plist_key]
            localizations[locale] = string_unit(localized_value)
        strings[plist_key] = {"localizations": localizations}

    output.write_text(
        json.dumps(
            {"sourceLanguage": "zh-Hans", "strings": strings, "version": "1.0"},
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def validate_placeholders(catalog: Path) -> None:
    document = json.loads(catalog.read_text(encoding="utf-8"))
    failures: list[str] = []
    for key, entry in document["strings"].items():
        expected = sorted(
            re.sub(r"^%\d+\$", "%", placeholder)
            for placeholder in PLACEHOLDER_PATTERN.findall(key)
        )
        for locale, localization in entry.get("localizations", {}).items():
            value = localization.get("stringUnit", {}).get("value", "")
            actual = sorted(
                re.sub(r"^%\d+\$", "%", placeholder)
                for placeholder in PLACEHOLDER_PATTERN.findall(value)
            )
            if expected != actual:
                failures.append(f"{locale}: {key!r} -> {value!r}")
    if failures:
        raise ValueError("placeholder validation failed:\n" + "\n".join(failures))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-catalog", required=True, type=Path)
    parser.add_argument(
        "--output", type=Path, default=Path("Tower/Localizable.xcstrings")
    )
    parser.add_argument(
        "--info-output", type=Path, default=Path("Tower/InfoPlist.xcstrings")
    )
    arguments = parser.parse_args()

    build_catalog(arguments.source_catalog, arguments.output)
    build_info_catalog(arguments.info_output)
    validate_placeholders(arguments.output)
    print(f"wrote {arguments.output} and {arguments.info_output}")


if __name__ == "__main__":
    main()
