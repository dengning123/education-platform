import { createEvaluationRouter } from "@/lib/evaluation/http-boundary";
import { createSupabaseEvaluationService } from "@/lib/evaluation/service";

export const dynamic = "force-dynamic";

const handler = createEvaluationRouter({ createService: createSupabaseEvaluationService });

export const POST = handler;
export const GET = handler;
export const PUT = handler;
export const PATCH = handler;
export const DELETE = handler;
export const OPTIONS = handler;
export const HEAD = handler;
