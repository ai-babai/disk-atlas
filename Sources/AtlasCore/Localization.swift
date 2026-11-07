import Foundation

public enum L10n {
    private static let lock = NSLock()
    private static var cachedLanguage = UserDefaults.standard.string(forKey: "atlas.language") ?? "ru"
    public static var language: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return cachedLanguage
        }
        set {
            lock.lock()
            cachedLanguage = newValue == "en" ? "en" : "ru"
            lock.unlock()
            UserDefaults.standard.set(newValue == "en" ? "en" : "ru", forKey: "atlas.language")
        }
    }
    public static func text(_ source: String) -> String {
        guard language == "en" else { return source }
        if let exact = english[source] { return exact }
        // Dynamic messages retain paths and values verbatim; only their UI phrases change.
        var result = source
        for (ru, en) in fragments { result = result.replacingOccurrences(of: ru, with: en) }
        if result.hasPrefix("Snapshot ·") || result.hasPrefix("Scan ·"), result.hasSuffix(" с") {
            result = String(result.dropLast(2)) + " s"
        }
        return result
    }
    public static func date(_ date: Date, time: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == "en" ? "en_US" : "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = time ? .short : .none
        return formatter.string(from: date)
    }
    public static func historyDate(_ date: Date) -> String {
        let locale = Locale(identifier: language == "en" ? "en_US" : "ru_RU")
        let time = date.formatted(.dateTime.locale(locale).hour().minute())
        if Calendar.current.isDateInToday(date) { return text("Сегодня") + " · " + time }
        if Calendar.current.isDateInYesterday(date) { return text("Вчера") + " · " + time }
        let day =
            Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date())
            ? date.formatted(.dateTime.locale(locale).day().month(.abbreviated))
            : date.formatted(.dateTime.locale(locale).day().month(.abbreviated).year())
        return day + " · " + time
    }
    private static let fragments: [(String, String)] = [
        ("Выбрано: ", "Selected: "), ("Ещё ", "More: "), ("Пропущено: ", "Skipped: "), ("Снимок · ", "Snapshot · "),
        (" объектов · ", " items · "), ("Анализ · ", "Scan · "), ("Типы: ", "Types: "), ("Фильтр: ", "Filter: "),
        ("Убрать ", "Remove "), (" из анализа", " from analysis"),
        ("Выбери папку для сканирования: ", "Choose a directory to scan: "),
        ("Нет доступа к папке: ", "Cannot access directory: "),
        ("Путь отсутствует в снимке: ", "Path is not in this snapshot: "),
        (" должен быть абсолютным путём.", " must be an absolute path."),
        ("Неизвестный инструмент: ", "Unknown tool: "),
        ("Неизвестный или повторный параметр: ", "Unknown or repeated option: "),
        ("Нет значения для ", "Missing value for "), ("Файл уже существует: ", "File already exists: "),
        (". Выбери новое имя.", ". Choose a new name."), ("Неизвестная команда: ", "Unknown command: "),
        (". Используй --help.", ". Use --help."), ("\nДвойной щелчок — открыть папку", "\nDouble-click to open folder"),
    ]
    private static let english: [String: String] = [
        "Все копии совпавшего файла остаются в группе.": "Every copy of a matching file stays in its group.",
        "На главную": "Home", "Сохранение отменено.": "Saving cancelled.", "Останавливаем…": "Stopping…",
        "Не удалось выделить память.": "Could not allocate memory.", "Файлов с копиями": "Files with copies",
        "Открыть дубликаты": "Open duplicates", "Открыть": "Open", "Новая проверка": "New check",
        "Новая проверка…": "New check…", "Оценить время": "Estimate time", "Фильтры результатов": "Result filters",
        "По сохранённой проверке": "From saved check", "Фильтруем результаты…": "Filtering results…",
        "Нет групп по этим фильтрам": "No groups match these filters", "Сбросить фильтры": "Reset filters",
        "Показаны только проверенные файлы": "Only checked files are shown", "Расширить проверку…": "Expand check…",
        "Сначала оценим время. Чтение файлов — только после запуска.":
            "Estimate first. Files are read only after you start.", "Быстрый просмотр": "Quick Look",
        "Быстрый просмотр · Пробел": "Quick Look · Space", "В корзину группу…": "Move group to Trash…",
        "В корзину копии группы": "Move group copies to Trash",

        "Все копии выбраны": "All copies selected",
        "В некоторых группах не останется копий": "Some groups will have no copies left",
        "Останется: ": "Will remain: ", "Останется": "Will remain",
        "Выбрать все копии группы для корзины": "Select every copy in this group for Trash",
        "Выбрать все копии группы": "Select every copy in this group",

        "Других копий: ": "Other copies: ", "Файлов: ": "Files: ", "Файлы с копиями": "Files with copies",
        "Некорректный суммарный размер файлов.": "Invalid total file size.", "Все группы": "All groups",
        "Переместить в Корзину?": "Move to Trash?", "Переместить в Корзину": "Move to Trash",
        "Проверь список. Выбранные файлы будут перемещены в Корзину; их можно восстановить через Finder.":
            "Review the list. Selected files will move to Trash and can be restored through Finder.",
        "Сохранится": "Keep this copy",
        "Выбрать повторы для корзины · одна копия останется": "Select repeats for Trash · keep one copy",
        "Выбрать повторы для корзины": "Select repeats for Trash", "В корзину повторы…": "Trash repeats…",
        "В корзину повторы": "Trash repeats", "Выбрать для корзины": "Select for Trash",
        "Хотя бы одна копия должна остаться": "At least one copy must stay", "В корзину…": "Move to Trash…",
        "В корзину": "Move to Trash", "Выбрано: ": "Selected: ", "Снять выбор": "Clear selection",
        "Готовим список…": "Preparing review…", "Проверяем копии…": "Rechecking copies…",
        "Перемещаем в Корзину…": "Moving to Trash…", "В корзине: ": "Moved to Trash: ",
        "Обнови анализ для актуальных размеров.": "Rescan to update storage sizes.",
        "Остановлено. Уже перемещённые файлы находятся в Корзине.": "Stopped. Files already moved are in Trash.",
        "Файлов с копиями: ": "Files with copies: ", "файлов с копиями": "files with copies",
        "Дубликаты внутри": "Duplicates inside",
        "Файлы с подтверждёнными копиями, включая вложенные папки": "Files with confirmed copies, including subfolders",
        "На диске — выделенные файлу блоки. Размер файлов — длина содержимого. Сжатие и разреженные файлы уменьшают место на диске; APFS-копии могут разделять блоки.":
            "On disk is the space allocated to a file. File size is the length of its contents. Compression and sparse files can use less disk space; APFS copies may share blocks.",
        "Выбери копии для корзины.": "Select copies for Trash.",
        "Выбор не соответствует отчёту. Повтори поиск дубликатов.":
            "Selection does not match the report. Run duplicate search again.",
        "В каждой группе должна остаться хотя бы одна копия.": "At least one copy must remain in each group.",
        "Некорректная группа или жёсткие ссылки. Повтори поиск дубликатов.":
            "Invalid group or hard links. Run duplicate search again.",
        "Файл вне области поиска или группа повреждена.": "File is outside the scan scope or the group is invalid.",
        "Содержимое копий различается. Повтори поиск дубликатов.":
            "Copies differ in content. Run duplicate search again.", "Загружаем отчёт…": "Loading report…",

        "Оценить поиск дубликатов": "Estimate duplicate search",
        "Проверить копии · явное readContents: true": "Compare copies · explicit readContents: true", "Пауза": "Pause",
        "Продолжить": "Resume", "Совпадения ещё не подтверждены": "No matches confirmed yet",
        "Показаны 1 000 объектов. Уточни поиск для остальных.":
            "Showing 1,000 entries. Refine your search to see more.",
        "Снимки содержат имена, пути, размеры и даты. Поиск дубликатов читает содержимое только по твоему выбору. Команд удаления нет.":
            "Snapshots contain names, paths, sizes and dates. Duplicate checks read content only when you opt in. No deletion commands.",
        "Сортировка": "Sort", "Повторный объём": "Repeated bytes", "Размер копии": "Copy size",
        "По убыванию": "Descending", "Как считается размер": "Size calculation", "Фильтры": "Filters",
        "После анализа — проверка в фоне. Чтение файлов может занять время.":
            "Checks run in the background after analysis. Reading files can take time.", "Отчёт": "Report",
        "Отчёт не сохранён": "Report not saved",
        "Снимки содержат имена, пути, размеры и даты. Чтение содержимого для дубликатов требует отдельного запуска. Команд удаления нет.":
            "Snapshots contain names, paths, sizes and dates. Duplicate content reading requires a separate explicit start. No deletion commands.",
        "Без минимума": "No minimum", "Параметры": "Options", "Любой размер": "Any size", "От ": "From ",
        "Крупные": "Large", "Мелкие": "Small", "Место на диске": "Disk usage", "Анализ": "Analysis", "Карта": "Map",
        "Отображение": "View", "Фильтры карты и списка": "Filter map and list", "Размер и дата": "Size and date",
        "Размер, дата и типы": "Size, date and types", "Найти дубликаты": "Find duplicates",
        "Долгая проверка содержимого. Сначала — оценка времени.":
            "Content comparison takes time. Review the estimate first.", "Файлы": "Files", "Копии": "Copies",
        "Повторы": "Repeated", "повторных копий": "in repeated copies", "групп": "groups",
        "Неполный результат": "Partial result", " чтения": " of reads", "Показать все копии": "Show all copies",
        "Отметить копию для отчёта": "Mark preferred copy in the report", "Дубликаты": "Duplicates",
        "Без ограничения": "No limit", "Минимальный размер": "Minimum size", "Максимальный размер": "Maximum size",
        "Ввести точные границы": "Enter exact bounds", "Включить фильтры": "Enable filters", "Групп: ": "Groups: ",
        "Давность выбирает группы с подходящей копией; более новые копии тоже сравниваются.":
            "Dates select groups with a matching copy; newer copies are compared too.", "До ": "Up to ",
        " чтения · ": " of reads · ", "До, пусто — без ограничения": "Maximum, leave empty for no limit",
        "Жёстких ссылок: ": "Hard-link aliases: ", "За последние 30 дней": "Last 30 days",
        "Искать в текущем снимке": "Search the current snapshot",
        "Карта и список · по данным снимка": "Map and list · snapshot data", "Любая дата": "Any date",
        "Начать проверку": "Start comparison", "Нет кандидатов для сравнения": "No candidates to compare",
        "Новые файлы после снимка попадут в поиск после повторного анализа. Облачные файлы без локального содержимого пропускаются.":
            "Rescan to include files added after this snapshot. Dataless cloud files are skipped.", "Оставить": "Keep",
        "«Оставить» — отметка для отчёта. Удаления файлов нет.":
            "Keep marks a preferred copy in the report. No files are deleted.",
        "Остальные копии доступны в экспорте.": "Export the report to see all copies.",
        "От, например 100 MB": "Minimum, e.g. 100 MB", "Отбираем кандидатов…": "Preparing candidates…",
        "Оценить проверку": "Estimate comparison",
        "Оценка грубая: зависит от диска и совпадений. Это чтение содержимого; файлы не изменяются.":
            "Rough estimate: disk speed and matches affect duration. File contents will be read; files stay unchanged.",
        "Оценка появится после подготовки": "Estimate available after preparation",
        "Параметры поиска": "Search options", "Пауза · основной анализ": "Paused · foreground analysis", "По": "To",
        "По снимку от ": "Snapshot from ", "Повторные копии: ": "Repeated copies: ",
        "Повторный объём не равен гарантированно освобождаемому месту: APFS может разделять блоки.":
            "Repeated bytes are not guaranteed reclaimable space: APFS may share blocks.",
        "Подготовить поиск дубликатов": "Prepare duplicate search", "Подробности пропусков": "Skipped file details",
        "Подтверждаем совпадения…": "Verifying matches…", "Подтверждённых групп: ": "Verified groups: ",
        "Показаны первые 500 групп. Полный результат доступен в экспорте.":
            "Showing the first 500 groups. Export for the full result.", "Показать": "Show", "Применить": "Apply",
        "Приостановлено": "Paused", "Проверено: ": "Checked: ", "Проверить снова": "Check again",
        "Проверь размер и порядок границ.": "Check the sizes and bound order.",
        "Проверяем начало и конец…": "Checking beginnings and endings…", "Пропущено: ": "Skipped: ", "С": "From",
        "Сбросить": "Reset", "Свой период": "Custom dates", "Совпадений не найдено": "No matches found",
        "Сортировать: ": "Sort by: ", "Сохраняем отчёт…": "Saving report…",
        "Сравниваем содержимое…": "Comparing contents…", "Старше 30 дней": "Older than 30 days",
        "Старше года": "Older than a year", "Типы": "Types", "Типы: ": "Types: ",
        "Файлов для сравнения: ": "Files to compare: ", "Файлы не изменяются": "Files stay unchanged",
        "Фильтры вида": "View filters", "Фильтр вида": "View filter", "Применяем фильтр…": "Applying filter…",
        "Читаем отчёт…": "Reading report…",
        "Чтение содержимого требует времени. После анализа покажем оценку и отдельно запросим запуск.":
            "Reading contents takes time. After analysis, review the estimate and start it separately.",
        "Экспорт отчёта…": "Export report…",
        "Эта проверка относится к другому снимку и продолжает работать в фоне.":
            "This comparison belongs to another snapshot and continues in the background.", "копий": "copies",
        "менее минуты": "under a minute", "мин": "min", "по ": "each ", "ч": "h",
        "Остановлено · неполный результат": "Stopped · partial result", "Проверка завершена": "Comparison complete",
        "Некорректный диапазон поиска.": "Invalid search range.",
        "Файл изменился или недоступен.": "File changed or is unavailable.",
        "Файл изменился во время проверки.": "File changed during comparison.",
        "Не удалось прочитать файл полностью.": "Could not read the complete file.",
        "Снимок больше не сохранён в истории.": "Snapshot is no longer in history.",
        "Слишком большой отчёт дубликатов.": "Duplicate report is too large.",
        "Недоступен, ссылка или файл только в облаке": "Unavailable, a link, or a dataless cloud file",
        "Некорректный путь файла.": "Invalid file path.", "Сбросить фильтр типов": "Clear file type filters",
        "Фильтр списка · несколько типов": "List filter · choose multiple", "Последние сканы": "Recent scans",
        "Удалить снимок": "Delete snapshot", "Снимок": "Snapshot", "до сжатия": "before compression",
        "Снимок не сохранён": "Snapshot not saved",
        "Оценка несжатых метаданных. После сохранения появится точный размер сжатого снимка.":
            "Estimated uncompressed metadata. The exact compressed size appears after saving.",
        "Размер сжатого файла снимка на диске. Исходные файлы в этот размер не входят.":
            "Size of the compressed snapshot file on disk. Source files are not included.",
        "Очистить историю?": "Clear scan history?", "Удалить снимок?": "Delete snapshot?",
        "Все снимки": "All snapshots",
        "Снимки и их метаданные будут удалены безвозвратно. Исходные файлы останутся на месте.":
            "Snapshots and their metadata will be permanently deleted. Your source files will stay in place.",
        "Удалить": "Delete", "Больше не спрашивать": "Don't ask again", "Подтверждать удаление": "Confirm deletion",
        "Удалить снимок…": "Delete snapshot…", "Очистить историю…": "Clear history…",
        "История очищена": "History cleared", "Снимок удалён": "Snapshot deleted", "История пуста": "No scans yet",
        "Снимков: ": "Snapshots: ", "Действия с историей": "History actions", "Сегодня": "Today", "Вчера": "Yesterday",
        "Читаем снимок…": "Reading snapshot…", "Готовим карту…": "Preparing the map…",
        "Сохраняем снимок…": "Saving snapshot…", "Открываем снимок": "Opening snapshot",
        "Сохранённые данные · без повторного анализа": "Saved data · no rescan", "Ищем…": "Searching…",
        "Создан": "Created", "Дата создания не сохранена в этом снимке": "Creation date was not saved in this snapshot",
        "История сканов": "Scan history", "История сканов…": "Scan history…", "Вся история…": "All scans…",
        "Здесь появятся сохранённые сканы": "Saved scans will appear here",
        "Сохранённые результаты. Открытие не запускает новый анализ.":
            "Saved results. Opening one does not start a new scan.", "Сохранение истории…": "Saving history…",
        "Не удалось открыть историю: ": "Could not open scan history: ",
        "Не удалось сохранить историю: ": "Could not save scan history: ", "Скрыть навигацию": "Hide sidebar",
        "Показать навигацию": "Show sidebar", "Скрыть подробности": "Hide details",
        "Показать подробности": "Show details", "Скрыть навигацию · ⌘B": "Hide sidebar · ⌘B",
        "Показать навигацию · ⌘B": "Show sidebar · ⌘B", "Скрыть подробности · ⌥⌘I": "Hide details · ⌥⌘I",
        "Показать подробности · ⌥⌘I": "Show details · ⌥⌘I", "Подготовка снимка…": "Preparing snapshot…",
        "Открыть весь снимок": "Open full snapshot", "Папки": "Folders", "Видео": "Video", "Аудио": "Audio",
        "Изображения": "Images", "Документы": "Documents", "Архивы": "Archives", "Код и данные": "Code & data",
        "Остальное": "Other", "Ссылки": "Links",
        "Нужен обычный файл снимка размером до 2 ГБ.": "Choose a regular snapshot file up to 2 GB.",
        "Неподдерживаемый или повреждённый снимок.": "Unsupported or damaged snapshot.",
        "Нарушена структура снимка.": "Invalid snapshot structure.",
        "Нарушены связи снимка.": "Invalid snapshot links.",
        "В снимке есть несвязанные объекты.": "The snapshot contains disconnected entries.",
        "Повреждены размеры снимка.": "Invalid snapshot sizes.",
        "Итоги снимка не совпадают с содержимым.": "Snapshot totals do not match its contents.",
        "Выбери хотя бы одну папку.": "Choose at least one folder.", "Выбранные папки": "Selected folders",
        "Не удалось прочитать папку.": "Could not read the folder.",
        "Другой том: сканируется отдельно.": "Another volume: add it as a separate scan location.",
        "Родительская папка недоступна.": "Parent directory is unavailable.",
        "Приложение не установлено: запусти scripts/build.sh --install.":
            "App is not installed: run scripts/build.sh --install.",
        "Не удалось открыть приложение.": "Could not open the app.",
        "Укажи либо path, либо непустой массив абсолютных paths.":
            "Supply either path or a nonempty array of absolute paths.",
        "Файл снимка уже существует. Выбери новое имя.": "Snapshot already exists. Choose a new name.",
        "limit: от 1 до 500.": "limit must be between 1 and 500.",
        "Укажи путь. Используй --help.": "Supply a path. Use --help.", "Новый анализ…": "New scan…",
        "Открыть снимок…": "Open snapshot…", "Сохранить снимок…": "Save snapshot…", "Сканирование": "Scan",
        "Повторить": "Rescan", "Остановить": "Stop", "На уровень выше": "Go up",
        "Контекст для агента": "Copy agent context", "Подробности": "Details", "На диске": "On disk",
        "Размер файлов": "File size", "Файлов": "Files", "Изменён": "Modified",
        "Жёсткая ссылка. Размер учтён у другого имени этого файла.":
            "Hard link. Its size is counted under another name for this file.", "Исследовать папку": "Explore folder",
        "Показать в Finder": "Show in Finder", "Скопировать путь": "Copy path",
        "Скопировать текущую папку и 30 крупных объектов в JSON · ⇧⌘C":
            "Copy this folder and 30 largest entries as JSON · ⇧⌘C",
        "APFS может разделять блоки между копиями. Размер здесь не равен гарантированно освобождаемому месту.":
            "APFS can share blocks between copies. These sizes are not guaranteed reclaimable space.",
        "Типы в папке": "File types", "Все": "All", "В папке пока нет файлов": "No files in this folder",
        "Один атлас. Два способа работать.": "One atlas. Two ways to work.",
        "Ты исследуешь карту. Агент получает те же данные через CLI или MCP и может открыть свой снимок в этом окне.":
            "Explore the map yourself, or let an agent use the same data through CLI or MCP and open its snapshot here.",
        "Подключение MCP": "MCP connection", "Копировать конфигурацию": "Copy configuration",
        "Сохранить текущий снимок…": "Save current snapshot…", "Доступные операции": "Available tools",
        "Просканировать папку и сохранить снимок": "Scan folders and save a snapshot",
        "Найти крупные файлы и исследовать папки": "Find large files and explore folders",
        "Открыть результат в приложении": "Open the result in the app",
        "Снимки содержат имена, пути, размеры и даты. Содержимое файлов не читается. Команд удаления нет.":
            "Snapshots contain names, paths, sizes and dates. File contents are not read. No deletion commands.",
        "Готово": "Done", "Нет занятых блоков": "No allocated blocks",
        "Папка пуста или данные недоступны.": "The folder is empty or unavailable.", "Открыть папку": "Open folder",
        "Место для важного": "Room for what matters", "Обзор": "Explore", "Карта пространства": "Space map",
        "Крупные файлы": "Largest files", "В этом анализе": "In this scan", "Добавить в анализ": "Add to scan",
        "Домашняя папка": "Home folder", "Загрузки": "Downloads", "Приложения": "Applications",
        "Другие папки…": "Other folders…", "Текущий снимок": "Current snapshot", "Данные на": "Data as of",
        "Анализ не завершён": "Incomplete scan", "Для агента": "For agents",
        "Локально на твоём Mac": "Local to your Mac", "Как в системе": "System appearance", "Светлая": "Light",
        "Тёмная": "Dark", "Оформление": "Appearance", "Оформление приложения": "App appearance",
        "Можно добавить только локальную папку или подключённый диск.": "Add a local folder or a mounted drive.",
        "Выбери папку, а не отдельный файл.": "Choose a folder, not an individual file.",
        "Пересекающиеся папки объединены: каждый файл учитывается один раз":
            "Overlapping folders merged: each file is counted once", "Выбрать": "Choose",
        "Выбери диск для анализа": "Choose a drive to analyze", "Выбери папку для анализа": "Choose folders to analyze",
        "Анализ остановлен · предыдущий снимок сохранён": "Scan stopped · previous snapshot kept",
        "Дождись завершения сканирования или останови его.": "Wait for the scan to finish or stop it first.",
        "Открыт сохранённый снимок": "Saved snapshot opened", "Снимок сохранён": "Snapshot saved",
        "Скопировано": "Copied", "Рабочий стол": "Desktop", "Музыка": "Music",
        "Добавь одну или несколько папок. Затем запусти анализ.": "Add one or more folders. Then start your scan.",
        "Весь диск Mac": "Mac data volume", "Перетащи сюда папки": "Drop folders here",
        "или добавь их кнопкой ниже": "or add them using the buttons below", "Добавить папки…": "Add folders…",
        "Другой диск…": "Another drive…", "Анализировать": "Analyze",
        "Включая вложенные папки · без повторного подсчёта\nФайлы не изменяются":
            "Includes subfolders · no double counting\nYour files stay unchanged",
        "Весь диск Mac · данные": "Mac · data volume", "Убрать из анализа": "Remove from scan",
        "Не удалось выполнить действие": "Could not complete the action", "Понятно": "OK",
        "Что будем анализировать?": "What would you like to analyze?", "Отмена": "Cancel",
        "На уровень выше · ⌘↑": "Go up · ⌘↑", "Обзор пространства": "Space overview",
        "Повторить сканирование · ⌘R": "Rescan · ⌘R", "Сохранить снимок · ⌘S": "Save snapshot · ⌘S",
        "Новый анализ": "New scan", "Карта папки": "Folder map", "Двойной щелчок — внутрь": "Double-click to explore",
        "Размер": "Size", "Выделенные блоки или логический размер файлов": "Allocated blocks or logical file size",
        "размер файлов в папке": "file size in this folder", "занято файлами в папке": "used by files in this folder",
        "файлов": "files", "свободно на томе при сканировании": "available on volume at scan time",
        "Содержимое": "Contents", "Найти файл или папку": "Find a file or folder",
        "Поиск по имени в текущей папке и вложенных папках": "Search by name in this folder and its subfolders",
        "Имя": "Name", "Размер ↓": "Size ↓", "На диске ↓": "On disk ↓", "Доля": "Share",
        "Первые 1 000 объектов. Уточни поиск для остальных.":
            "Showing the first 1,000 entries. Refine your search to see more.", "Ничего не найдено": "No matches",
        "Сканирование…": "Scanning…", "Собираем карту файлов.": "Mapping your files.", "Остановить анализ": "Stop scan",
        "Открыть сохранённый снимок…": "Open a saved snapshot…", "Без облака": "No cloud",
        "Только метаданные": "Metadata only", "Остановлено · неполный снимок": "Stopped · incomplete snapshot",
        "Готово к сканированию": "Ready to scan", "Файлы остаются на своих местах": "Your files stay in place",
        "Что не удалось прочитать": "What could not be read",
        "Недоступные папки не входят в итог. Для защищённых папок macOS может потребоваться полный доступ к диску в Системных настройках.":
            "Unavailable folders are excluded from totals. Protected macOS folders may require Full Disk Access in System Settings.",
        "Сохранены первые 200 сообщений": "First 200 messages retained", "Копировать команды": "Copy commands",
        "Фильтр списка": "List filter", "Открыть результаты поиска дубликатов": "Open duplicate results",
        "Остановлено": "Stopped",
        "История доступна через history. Справка для агента — disk-atlas schema.":
            "Reuse saved scans with history. Discover commands with disk-atlas schema.",
    ]
}
