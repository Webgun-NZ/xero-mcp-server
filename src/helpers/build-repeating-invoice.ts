import {
  LineAmountTypes,
  LineItemTracking,
  RepeatingInvoice,
  Schedule,
} from "xero-node";

export interface RepeatingInvoiceLineItem {
  description: string;
  quantity: number;
  unitAmount: number;
  accountCode: string;
  taxType: string;
  itemCode?: string;
  tracking?: LineItemTracking[];
}

export interface RepeatingInvoiceInput {
  contactId: string;
  type: "ACCREC" | "ACCPAY";
  lineItems: RepeatingInvoiceLineItem[];
  period: number;
  unit: "WEEKLY" | "MONTHLY";
  startDate: string;
  dueDate: number;
  dueDateType: keyof typeof Schedule.DueDateTypeEnum;
  endDate?: string;
  reference?: string;
  lineAmountTypes?: keyof typeof LineAmountTypes;
  status?: "DRAFT" | "AUTHORISED";
  approvedForSending?: boolean;
  sendCopy?: boolean;
  markAsSent?: boolean;
  includePDF?: boolean;
}

const isoDate = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Builds the RepeatingInvoice payload for the Xero API and rejects
 * combinations Xero would refuse (or silently ignore).
 */
export const buildRepeatingInvoice = (
  input: RepeatingInvoiceInput,
): RepeatingInvoice => {
  if (!isoDate.test(input.startDate)) {
    throw new Error("startDate must be in YYYY-MM-DD format");
  }
  if (input.endDate !== undefined) {
    if (!isoDate.test(input.endDate)) {
      throw new Error("endDate must be in YYYY-MM-DD format");
    }
    if (input.endDate < input.startDate) {
      throw new Error("endDate must be on or after startDate");
    }
  }
  if (!Number.isInteger(input.period) || input.period < 1) {
    throw new Error("period must be a whole number of 1 or more");
  }
  if (!Number.isInteger(input.dueDate) || input.dueDate < 0) {
    throw new Error("dueDate must be a whole number of 0 or more");
  }
  if (input.lineItems.length === 0) {
    throw new Error("At least one line item is required");
  }

  const status = input.status ?? "DRAFT";
  // Automatic emailing only applies to approved sales invoices.
  if (input.approvedForSending) {
    if (input.type !== "ACCREC") {
      throw new Error("approvedForSending is only valid for ACCREC invoices");
    }
    if (status !== "AUTHORISED") {
      throw new Error("approvedForSending requires status AUTHORISED");
    }
  }
  if (
    !input.approvedForSending &&
    (input.sendCopy || input.markAsSent || input.includePDF)
  ) {
    throw new Error(
      "sendCopy, markAsSent and includePDF require approvedForSending",
    );
  }

  return {
    type: RepeatingInvoice.TypeEnum[input.type],
    contact: { contactID: input.contactId },
    schedule: {
      period: input.period,
      unit: Schedule.UnitEnum[input.unit],
      dueDate: input.dueDate,
      dueDateType: Schedule.DueDateTypeEnum[input.dueDateType],
      startDate: input.startDate,
      ...(input.endDate ? { endDate: input.endDate } : {}),
    },
    lineItems: input.lineItems,
    ...(input.lineAmountTypes
      ? { lineAmountTypes: LineAmountTypes[input.lineAmountTypes] }
      : {}),
    ...(input.reference ? { reference: input.reference } : {}),
    status: RepeatingInvoice.StatusEnum[status],
    ...(input.approvedForSending
      ? {
          approvedForSending: true,
          sendCopy: input.sendCopy ?? false,
          markAsSent: input.markAsSent ?? false,
          includePDF: input.includePDF ?? true,
        }
      : {}),
  };
};
