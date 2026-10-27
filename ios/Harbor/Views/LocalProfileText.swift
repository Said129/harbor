import Foundation

enum LocalProfileText {
    enum Key: CaseIterable, Equatable { case sharedContinue, requiredAddon }
    static let translations: [String: [String]] = [
        "en": ["Each Harbor profile can keep its own progress, separate from profiles that share the same sources.", "Install this addon in Harbor first so its titles can be loaded."],
        "es": ["Cada perfil de Harbor puede guardar su propio progreso, separado de los perfiles que comparten las mismas fuentes.", "Instala primero este addon en Harbor para poder cargar sus títulos."],
        "de": ["Jedes Harbor-Profil kann seinen eigenen Fortschritt getrennt von Profilen speichern, die dieselben Quellen nutzen.", "Installiere dieses Addon zuerst in Harbor, damit seine Titel geladen werden können."],
        "fr": ["Chaque profil Harbor peut conserver sa propre progression, séparément des profils qui partagent les mêmes sources.", "Installez d’abord cet addon dans Harbor pour pouvoir charger ses titres."],
        "it": ["Ogni profilo Harbor può conservare i propri progressi, separati dai profili che condividono le stesse fonti.", "Installa prima questo addon in Harbor per poter caricare i suoi titoli."],
        "pt": ["Cada perfil do Harbor pode guardar o seu próprio progresso, separado dos perfis que partilham as mesmas fontes.", "Instale primeiro este addon no Harbor para poder carregar os seus títulos."],
        "ru": ["Каждый профиль Harbor может хранить собственный прогресс отдельно от профилей с теми же источниками.", "Сначала установите это дополнение в Harbor, чтобы загрузить его материалы."],
        "pl": ["Każdy profil Harbor może zachować własne postępy, niezależnie od profili korzystających z tych samych źródeł.", "Najpierw zainstaluj ten dodatek w Harbor, aby można było załadować jego tytuły."],
        "tr": ["Her Harbor profili, aynı kaynakları paylaşan profillerden ayrı olarak kendi ilerlemesini tutabilir.", "İçeriklerinin yüklenebilmesi için önce bu eklentiyi Harbor'a yükleyin."],
        "ar": ["يمكن لكل ملف شخصي في Harbor حفظ تقدّمه بشكل مستقل عن الملفات التي تشترك في المصادر نفسها.", "ثبّت هذه الإضافة في Harbor أولاً لتتمكّن من تحميل محتواها."],
        "ja": ["各Harborプロフィールは、同じソースを共有する他のプロフィールとは別に視聴状況を保存できます。", "作品を読み込むには、まずこのアドオンをHarborにインストールしてください。"],
        "ko": ["각 Harbor 프로필은 같은 소스를 공유하는 다른 프로필과 별도로 시청 기록을 저장할 수 있습니다.", "작품을 불러오려면 먼저 이 애드온을 Harbor에 설치하세요."],
        "zh": ["每个 Harbor 个人资料都可以独立保存观看进度，不与使用相同来源的其他个人资料混合。", "请先在 Harbor 中安装此插件，才能加载其内容。"],
        "hi": ["हर Harbor प्रोफ़ाइल अपनी प्रगति को समान स्रोत इस्तेमाल करने वाली अन्य प्रोफ़ाइल से अलग रख सकती है।", "इसके शीर्षक लोड करने के लिए पहले यह ऐडऑन Harbor में इंस्टॉल करें।"],
        "vi": ["Mỗi hồ sơ Harbor có thể lưu tiến độ riêng, tách biệt với các hồ sơ dùng chung nguồn.", "Hãy cài tiện ích này trong Harbor trước để có thể tải các nội dung của nó."],
        "id": ["Setiap profil Harbor dapat menyimpan progresnya sendiri, terpisah dari profil yang memakai sumber yang sama.", "Instal addon ini di Harbor terlebih dahulu agar judulnya dapat dimuat."],
    ]
    static func value(_ key: Key, language: String? = nil) -> String {
        let code = InterfaceLanguage.resolve(language ?? UserDefaults.standard.string(forKey: "uiLanguage") ?? "es")
        let index = key == .sharedContinue ? 0 : 1
        return (translations[code] ?? translations["en"]!)[index]
    }
}
