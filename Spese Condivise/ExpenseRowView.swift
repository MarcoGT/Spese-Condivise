//
//  ExpenseRowView.swift
//  Spese Condivise
//
//  Created by Marco on 15.12.25.
//


import SwiftUI
import CoreData

struct ExpenseRowView: View {

    @ObservedObject var expense: Expense

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(expense.note ?? "")
                    .font(.headline)

                Text(expense.date ?? Date(), style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(String(format: "%.2f €", expense.amount))
                .foregroundColor(expense.paidByMe ? .green : .red)
        }
    }
}