import { z } from "zod";
import { createXeroRepeatingInvoice } from "../../handlers/create-xero-repeating-invoice.handler.js";
import { CreateXeroTool } from "../../helpers/create-xero-tool.js";
import { formatRepeatingInvoice } from "../../helpers/format-repeating-invoice.js";

const trackingSchema = z.object({
  name: z.string().describe("The name of the tracking category. Can be obtained from the list-tracking-categories tool"),
  option: z.string().describe("The name of the tracking option. Can be obtained from the list-tracking-categories tool"),
  trackingCategoryID: z.string().describe("The ID of the tracking category. \
    Can be obtained from the list-tracking-categories tool"),
});

const lineItemSchema = z.object({
  description: z.string().describe("The description of the line item"),
  quantity: z.number().describe("The quantity of the line item"),
  unitAmount: z.number().describe("The price per unit of the line item"),
  accountCode: z.string().describe("The account code of the line item - can be obtained from the list-accounts tool"),
  taxType: z.string().describe("The tax type of the line item - can be obtained from the list-tax-rates tool"),
  itemCode: z.string().describe("The item code of the line item - can be obtained from the list-items tool \
    If the item is not listed, add without an item code and ask the user if they would like to add an item code.").optional(),
  tracking: z.array(trackingSchema).describe("Up to 2 tracking categories and options can be added to the line item. \
    Can be obtained from the list-tracking-categories tool. \
    Only use if prompted by the user.").optional(),
});

const CreateRepeatingInvoiceTool = CreateXeroTool(
  "create-repeating-invoice",
  "Create a repeating invoice template in Xero. Xero then generates an invoice on every scheduled date. \
 With status AUTHORISED and approvedForSending true, each generated sales invoice is approved and emailed \
 to the contact's email address automatically, so confirm the schedule, amounts and recipient with the user first. \
 With status DRAFT, each generated invoice is saved as a draft for review.",
  {
    contactId: z.string().describe("The ID of the contact to invoice. \
      Can be obtained from the list-contacts tool."),
    type: z.enum(["ACCREC", "ACCPAY"]).describe("ACCREC for sales invoices, ACCPAY for bills."),
    lineItems: z.array(lineItemSchema).min(1),
    period: z.number().int().min(1).describe("How many units between invoices, e.g. 1 with unit MONTHLY for every month."),
    unit: z.enum(["WEEKLY", "MONTHLY"]).describe("The schedule unit."),
    startDate: z.string().describe("The date of the first invoice (YYYY-MM-DD format)."),
    endDate: z.string().describe("The date after which no more invoices are generated (YYYY-MM-DD format). \
      Leave out for no end date.").optional(),
    dueDate: z.number().int().min(0).describe("The number used with dueDateType, e.g. 3 with DAYSAFTERBILLDATE \
      makes each invoice due 3 days after it is raised."),
    dueDateType: z.enum([
      "DAYSAFTERBILLDATE",
      "DAYSAFTERBILLMONTH",
      "OFCURRENTMONTH",
      "OFFOLLOWINGMONTH",
    ]).describe("How dueDate is applied: DAYSAFTERBILLDATE (days after the invoice date), \
      DAYSAFTERBILLMONTH (days after the end of the invoice month), \
      OFCURRENTMONTH (day of the invoice month), OFFOLLOWINGMONTH (day of the following month)."),
    lineAmountTypes: z.enum(["Exclusive", "Inclusive", "NoTax"]).describe("Whether unit amounts exclude or include tax. \
      Defaults to the organisation setting.").optional(),
    reference: z.string().describe("A reference for the generated invoices.").optional(),
    status: z.enum(["DRAFT", "AUTHORISED"]).describe("DRAFT saves generated invoices as drafts. \
      AUTHORISED approves them. Defaults to DRAFT.").optional(),
    approvedForSending: z.boolean().describe("Email each generated invoice to the contact automatically. \
      Requires type ACCREC and status AUTHORISED.").optional(),
    sendCopy: z.boolean().describe("Send a copy of each email to the user who created the template. \
      Requires approvedForSending.").optional(),
    markAsSent: z.boolean().describe("Mark each generated invoice as sent. Requires approvedForSending.").optional(),
    includePDF: z.boolean().describe("Attach a PDF of the invoice to each email. Requires approvedForSending. \
      Defaults to true when approvedForSending is set.").optional(),
  },
  async (input) => {
    const result = await createXeroRepeatingInvoice(input);
    if (result.isError) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error creating repeating invoice: ${result.error}`,
          },
        ],
      };
    }

    return {
      content: [
        {
          type: "text" as const,
          text: `Repeating invoice created successfully:\n${formatRepeatingInvoice(result.result, true)}`,
        },
      ],
    };
  },
);

export default CreateRepeatingInvoiceTool;
