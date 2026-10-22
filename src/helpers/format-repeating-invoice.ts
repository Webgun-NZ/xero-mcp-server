import { RepeatingInvoice } from "xero-node";
import { formatLineItem } from "./format-line-item.js";

export const formatRepeatingInvoice = (
  repeatingInvoice: RepeatingInvoice,
  includeLineItems: boolean = false,
): string => {
  const schedule = repeatingInvoice.schedule;
  return [
    `Repeating Invoice ID: ${repeatingInvoice.repeatingInvoiceID}`,
    `Type: ${repeatingInvoice.type || "Unknown"}`,
    `Status: ${repeatingInvoice.status || "Unknown"}`,
    repeatingInvoice.contact
      ? `Contact: ${repeatingInvoice.contact.name} (${repeatingInvoice.contact.contactID})`
      : null,
    repeatingInvoice.reference
      ? `Reference: ${repeatingInvoice.reference}`
      : null,
    schedule
      ? `Repeats: every ${schedule.period} ${schedule.unit}`
      : null,
    schedule?.startDate ? `Start Date: ${schedule.startDate}` : null,
    schedule?.nextScheduledDate
      ? `Next Scheduled Date: ${schedule.nextScheduledDate}`
      : null,
    schedule?.endDate ? `End Date: ${schedule.endDate}` : null,
    schedule
      ? `Due: ${schedule.dueDate} ${schedule.dueDateType}`
      : null,
    repeatingInvoice.lineAmountTypes
      ? `Line Amount Types: ${repeatingInvoice.lineAmountTypes}`
      : null,
    `Sub Total: ${repeatingInvoice.subTotal ?? 0}`,
    `Total Tax: ${repeatingInvoice.totalTax ?? 0}`,
    `Total: ${repeatingInvoice.total ?? 0}`,
    `Approved For Sending: ${repeatingInvoice.approvedForSending ? "Yes" : "No"}`,
    repeatingInvoice.approvedForSending
      ? `Send Copy: ${repeatingInvoice.sendCopy ? "Yes" : "No"}, Mark As Sent: ${repeatingInvoice.markAsSent ? "Yes" : "No"}, Include PDF: ${repeatingInvoice.includePDF ? "Yes" : "No"}`
      : null,
    includeLineItems
      ? `Line Items: ${repeatingInvoice.lineItems?.map(formatLineItem)}`
      : null,
  ]
    .filter(Boolean)
    .join("\n");
};
