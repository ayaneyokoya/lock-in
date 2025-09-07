//
//  MotivationQuoteFetch.swift
//  Lock In
//
//  Created by Zhi on 9/6/25.
//
// I need to create a data model for the daily quotes, I need the mainly need the content and author
import SwiftUI
import Foundation

// MARK: QuoteModel
struct QuoteModel: Decodable, Identifiable {
    let id: Int
    let quote: String
    let author: String
}

// MARK: ViewModel
@MainActor
final class MotivationQuoteFetch: ObservableObject {
    @Published var quoteModel: QuoteModel?
    @Published var isFetching = false
    @Published var error: String?
    
    init() {
        Task { await fetchQuote() }
    }
    
    func load() {
        Task { await fetchQuote() }
    }
    
    func refresh() {
        Task { await fetchQuote() }
    }
    
    private func makeURL() -> URL {
        URL(string: "https://dummyjson.com/quotes/random")!
    }
    
    private func fetchQuote() async {
        isFetching = true
        error = nil
        defer { isFetching = false }
        
        do {
            let (data, resp) = try await URLSession.shared.data(from: makeURL())
            guard let http = resp as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let q = try JSONDecoder().decode(QuoteModel.self, from: data)
            self.quoteModel = q
        } catch {
            self.quoteModel = QuoteModel(id: -1,
                quote: "A task a day keeps the bad things away. IDK JUST DO IT!", author: "Zhi")
            self.error = "A network issue has occured"
        }
    }
}

// MARK: View
struct QuoteCardView: View {
    @StateObject private var vm = MotivationQuoteFetch()

    var body: some View {
        Group {
            if vm.isFetching && vm.quoteModel == nil {
                ProgressView("Fetching motivation…").padding()
            } else if let q = vm.quoteModel {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Quote of the Day")
                            .font(.headline)
                        Spacer()
                        Button { vm.refresh() } label: {
                            Image(systemName: "arrow.clockwise")
                                .imageScale(.medium)
                        }
                        .buttonStyle(.borderless)
                    }
                    Text("“\(q.quote)”")
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("— \(q.author)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
                .padding(.horizontal)
            }
        }
        .task { vm.load() }
    }
}
