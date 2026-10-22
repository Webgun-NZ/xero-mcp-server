import { z } from "zod";
import { deleteXeroRepeatingInvoice } from "../../handlers/delete-xero-repeating-invoice.handler.js";
import { CreateXeroTool } from "../../helpers/create-xero-tool.js";
import { formatRepeatingInvoice } from "../../helpers/format-repeating-invoice.js";

const DeleteRepeatingInvoiceTool = CreateXeroTool(
  "delete-repeating-invoice",
  "Delete a repeating invoice template in Xero so it stops generating invoices. \
  Invoices it has already generated are not affected. This cannot be undone, so confirm with the user first.",
  {
    repeatingInvoiceId: z
      .string()
      .uuid()
      .describe("The ID of the repeating invoice. Can be obtained from the list-repeating-invoices tool."),
  },
  async ({ repeatingInvoiceId }) => {
    const result = await deleteXeroRepeatingInvoice(repeatingInvoiceId);
    if (result.isError) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error deleting repeating invoice: ${result.error}`,
          },
        ],
      };
    }

    return {
      content: [
        {
          type: "text" as const,
          text: `Repeating invoice deleted:\n${formatRepeatingInvoice(result.result)}`,
        },
      ],
    };
  },
);

export default DeleteRepeatingInvoiceTool;
