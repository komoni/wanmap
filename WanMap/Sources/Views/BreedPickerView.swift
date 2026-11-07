import SwiftUI

/// 犬種を選ぶ画面（設定タブ「自分の犬」から開く）
/// - 数百種になっても探せるよう、検索と並び替え（人気順／50音順／サイズ順）を必須装備にする。
/// - 検索は和名・読み・英名・別名が対象で、ひらがな/カタカナ・全角半角の揺れを吸収する（BreedStore）。
/// - 犬種をタップしたら即選択して前の画面に戻る（決定ボタンは置かない）。
/// - 見つからない・分からない場合の逃げ道（その他の犬種／設定しない）を常に出す。
/// - 開いた直後はキーボードを自動表示しない（人気犬種がそのまま見えて1タップで選べるように）。
struct BreedPickerView: View {
    @Environment(BreedStore.self) private var breedStore
    @Environment(MarkerSettings.self) private var markerSettings
    @Environment(\.dismiss) private var dismiss

    /// 現在選ばれている犬種ID（チェック表示用）
    let currentBreedId: String?
    /// 選択時のコールバック（nil は「設定しない」）
    let onSelect: (String?) -> Void

    @State private var query = ""

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var searchResults: [Breed] {
        breedStore.search(query, sort: markerSettings.breedSort,
                          ascending: markerSettings.breedSortAscending)
    }

    var body: some View {
        @Bindable var markerSettings = markerSettings
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("犬種を検索（例：しば、トイプー）", text: $query)
                        .accessibilityIdentifier("breedSearchField")
                    if isSearching {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("検索をクリア")
                    }
                }
                HStack {
                    Text("並び替え")
                    Spacer()
                    Picker("並び替え", selection: $markerSettings.breedSort) {
                        ForEach(BreedSort.allCases, id: \.self) { sort in
                            Text(sort.displayName).tag(sort)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("breedSortPicker")
                    // 並びの向き（上から＝昇順／下から＝降順）の切り替え
                    Button {
                        markerSettings.breedSortAscending.toggle()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: markerSettings.breedSortAscending
                                  ? "arrow.up" : "arrow.down")
                            Text(markerSettings.breedSortAscending ? "上から" : "下から")
                        }
                        .font(.caption)
                    }
                    .accessibilityIdentifier("breedSortDirectionButton")
                    .accessibilityLabel(markerSettings.breedSortAscending
                                        ? "上から並び替え中。下からに切り替える"
                                        : "下から並び替え中。上からに切り替える")
                }
            }

            if isSearching {
                if searchResults.isEmpty {
                    Section("見つかりませんでした") {
                        Text("別の読みや別名でも探せます（例：シェルティ）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        specialRows
                    }
                } else {
                    Section {
                        ForEach(searchResults) { breed in
                            breedRow(breed)
                        }
                    }
                }
            } else {
                switch markerSettings.breedSort {
                case .popularity:
                    Section {
                        ForEach(breedStore.sorted(breedStore.breeds, by: .popularity,
                                                  ascending: markerSettings.breedSortAscending)) { breed in
                            breedRow(breed)
                        }
                    }
                case .kana:
                    ForEach(kanaSections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.breeds) { breed in
                                breedRow(breed)
                            }
                        }
                    }
                case .size:
                    ForEach(sizeSections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.breeds) { breed in
                                breedRow(breed)
                            }
                        }
                    }
                }
                Section("見つからない・わからない") {
                    specialRows
                }
            }
        }
        .navigationTitle("犬種を選ぶ")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 行

    private func breedRow(_ breed: Breed) -> some View {
        Button {
            onSelect(breed.id)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(breed.name)
                        .foregroundStyle(.primary)
                    Text("\(breed.size.displayName)・\(breed.english)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if breed.id == currentBreedId {
                    Image(systemName: "checkmark")
                        .foregroundStyle(WanStyle.coral)
                }
            }
        }
        .accessibilityIdentifier("breedRow_\(breed.id)")
    }

    /// 逃げ道の行：その他の犬種／犬種を設定しない
    @ViewBuilder
    private var specialRows: some View {
        if let other = breedStore.breed(id: "other") {
            breedRow(other)
        }
        Button {
            onSelect(nil)
            dismiss()
        } label: {
            HStack {
                Text("犬種を設定しない")
                    .foregroundStyle(.primary)
                Spacer()
                if currentBreedId == nil {
                    Image(systemName: "checkmark")
                        .foregroundStyle(WanStyle.coral)
                }
            }
        }
        .accessibilityIdentifier("breedRow_none")
    }

    // MARK: - セクション分け

    private struct BreedSection {
        let title: String
        let breeds: [Breed]
    }

    /// 50音順：読みの最初の文字で「あ行」などに分ける
    private var kanaSections: [BreedSection] {
        let rows: [(title: String, chars: String)] = [
            ("あ行", "あいうえお"), ("か行", "かきくけこがぎぐげご"),
            ("さ行", "さしすせそざじずぜぞ"), ("た行", "たちつてとだぢづでど"),
            ("な行", "なにぬねの"), ("は行", "はひふへほばびぶべぼぱぴぷぺぽ"),
            ("ま行", "まみむめも"), ("や行", "やゆよ"),
            ("ら行", "らりるれろ"), ("わ行", "わをん"),
        ]
        let sortedBreeds = breedStore.sorted(breedStore.breeds, by: .kana,
                                             ascending: markerSettings.breedSortAscending)
        var sections: [BreedSection] = []
        for row in rows {
            let members = sortedBreeds.filter { breed in
                guard let first = breed.kana.first else { return false }
                return row.chars.contains(first)
            }
            if !members.isEmpty {
                sections.append(BreedSection(title: row.title, breeds: members))
            }
        }
        let grouped = Set(sections.flatMap(\.breeds).map(\.id))
        let rest = sortedBreeds.filter { !grouped.contains($0.id) }
        if !rest.isEmpty {
            sections.append(BreedSection(title: "その他", breeds: rest))
        }
        // 下から（降順）では行セクションの順も逆にする（わ行→あ行）
        return markerSettings.breedSortAscending ? sections : sections.reversed()
    }

    private var sizeSections: [BreedSection] {
        let ascending = markerSettings.breedSortAscending
        let sizes = BreedSize.allCases
            .sorted { ascending ? $0.sortOrder < $1.sortOrder : $0.sortOrder > $1.sortOrder }
        return sizes
            .map { size in
                BreedSection(title: size.displayName,
                             breeds: breedStore.sorted(
                                breedStore.breeds.filter { $0.size == size },
                                by: .kana, ascending: ascending))
            }
            .filter { !$0.breeds.isEmpty }
    }
}
