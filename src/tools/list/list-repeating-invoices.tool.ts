import { z } from "zod";
import { listXeroRepeatingInvoices } from "../../handlers/list-xero-repeating-invoices.handler.js";
import { CreateXeroTool } from "../../helpers/create-xero-tool.js";
import { formatRepeatingInvoice } from "../../helpers/format-repeating-invoice.js";

const ListRepeatingInvoicesTool = CreateXeroTool(
  "list-repeating-invoices",
  "List repeating invoice templates in Xero, with their schedule, next scheduled date and whether \
  generated invoices are emailed automatically. Optionally filter to one contact.",
  {
    contactId: z
      .string()
      .uuid()
      .describe("Only list repeating invoices for this contact. Can be obtained from the list-contacts tool.")
      .optional(),
    includeLineItems: z.boolean().describe("Also return each template's line items.").optional(),
  },
  async ({ contactId, includeLineItems }) => {
    const response = await listXeroRepeatingInvoices(contactId);
    if (response.error !== null) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error listing repeating invoices: ${response.error}`,
          },
        ],
      };
    }

    const repeatingInvoices = response.result;

    return {
      content: [
        {
          type: "text" as const,
          text: `Found ${repeatingInvoices?.length || 0} repeating invoices:`,
        },
        ...(repeatingInvoices?.map((repeatingInvoice) => ({
          type: "text" as const,
          text: formatRepeatingInvoice(repeatingInvoice, includeLineItems ?? false),
        })) || []),
      ],
    };
  },
);

export default ListRepeatingInvoicesTool;
