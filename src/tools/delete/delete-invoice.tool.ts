import { z } from "zod";
import { deleteXeroInvoice } from "../../handlers/delete-xero-invoice.handler.js";
import { CreateXeroTool } from "../../helpers/create-xero-tool.js";

const DeleteInvoiceTool = CreateXeroTool(
  "delete-invoice",
  "Delete an invoice in Xero. Only works on draft or awaiting-approval invoices; \
  approved invoices are refused. This cannot be undone, so confirm with the user first.",
  {
    invoiceId: z
      .string()
      .uuid()
      .describe("The ID of the invoice. Can be obtained from the list-invoices tool."),
  },
  async ({ invoiceId }) => {
    const result = await deleteXeroInvoice(invoiceId);
    if (result.isError) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Error deleting invoice: ${result.error}`,
          },
        ],
      };
    }

    const invoice = result.result;

    return {
      content: [
        {
          type: "text" as const,
          text: [
            "Invoice deleted:",
            `ID: ${invoice?.invoiceID}`,
            `Invoice: ${invoice?.invoiceNumber}`,
            `Contact: ${invoice?.contact?.name}`,
            `Total: ${invoice?.total}`,
            `Status: ${invoice?.status}`,
          ].join("\n"),
        },
      ],
    };
  },
);

export default DeleteInvoiceTool;
