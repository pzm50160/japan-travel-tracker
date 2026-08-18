// ============================================================
//  scan-receipt — 收據辨識的後端代理
//
//  為什麼要有這支：
//    原本前端直接呼叫 Anthropic API，金鑰存在每支手機的
//    localStorage 裡。這代表 (1) 每位旅伴都要自己申請金鑰，
//    (2) 金鑰放在瀏覽器可被竊取。改由這支函式代呼叫後，
//    金鑰只存在 Supabase 的環境變數，手機端完全看不到。
//
//  誰可以用：已登入且至少屬於一個旅程的人（含免註冊的匿名身分）。
//    不做這層檢查的話，任何註冊帳號都能拿你的金鑰額度用。
//
//  部署後要設定的環境變數：ANTHROPIC_API_KEY
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MODEL = "claude-sonnet-4-6";
const MAX_IMAGE_BYTES = 6 * 1024 * 1024; // 前端已縮到 300KB 上下，留寬裕上限擋濫用

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const RECEIPT_PROMPT = `你是頂尖的日本收據辨識專家，精通日文、熟悉日本各類消費場所（超市、便利商店、餐廳、居酒屋、百貨公司、藥妝店）的商品與菜單。請逐字仔細辨識收據圖片中每個品項，給出最精確的繁體中文翻譯。

【辨識原則】
1. 完整讀取每一行文字，品名與金額分開辨識，不要混淆
2. 有數量標示（個/本/枚/杯/人）的要正確抓取數量
3. 沒有金額或金額為0的品項（如免費冰水お冷、備註文字）不要列入
4. 條碼編號、商品編號開頭的數字忽略，只取品名
5. 翻譯貼近台灣繁體中文用語

【蔬果生鮮】
タマネギ/玉ねぎ=洋蔥、ニンジン/人参=紅蘿蔔、キャベツ=高麗菜、ジャガイモ=馬鈴薯、サツマイモ=地瓜、ブロッコリー=花椰菜、ホウレンソウ=菠菜、トマト=番茄、キュウリ=小黃瓜、ナス=茄子、ピーマン=青椒、ゴボウ=牛蒡、レンコン=蓮藕、アシタバ=明日葉、枝豆=毛豆、デラウエア=特拉華葡萄、イチゴ=草莓、バナナ=香蕉、リンゴ=蘋果、ミカン=橘子、スイカ=西瓜

【肉・魚・海鮮】
牛肉=牛肉、豚肉=豬肉、鶏肉/とり=雞肉、鶏テキ=照燒雞腿排、カルビ=牛/豬肋排、ロース=里肌肉、ミンチ=絞肉、サーモン=鮭魚、まぐろ=鮪魚、えび=蝦、いか=花枝、たこ=章魚、かに=螃蟹、カニカマ=蟹肉棒、あさり=蛤蜊、しじみ=蜆、ほたて=干貝、さば=鯖魚、さんま=秋刀魚、鮭=鮭魚

【餐廳・居酒屋菜單】
焼おにぎり=烤飯糰、おにぎり=飯糰、チャージ料/お通し代=座位費、テーブルチャージ=桌位費、サービス料=服務費、GW料金=黃金週附加費、石焼=石鍋、クッパ=韓式湯飯（牛肉湯泡飯）、ビビンバ=石鍋拌飯、チゲ=韓式鍋、カルビクッパ=牛小排韓式湯飯、じゃがバター=奶油烤馬鈴薯、唐揚げ=炸雞塊、とんかつ=日式炸豬排、天ぷら=天婦羅、焼きとり=烤雞串、串カツ=炸串、餃子=煎餃、ラーメン=拉麵、うどん=烏龍麵、そば=蕎麥麵、スパゲ/スパゲッティ=義大利麵、ミートソース=肉醬、ピザ=披薩、カレー=咖哩、丼=丼飯、寿司/鮨=壽司、にぎり=握壽司、刺身=生魚片、焼肉=烤肉、しゃぶしゃぶ=涮涮鍋、すき焼き=壽喜燒

【飲料・酒】
生ビール/生=生啤酒、一番搾り=麒麟一番搾生啤酒、ハイボール=威士忌蘇打、サワー=沙瓦（酸甜調酒）、チューハイ=調酒、梅酒=梅酒、日本酒/清酒=清酒、焼酎=燒酎、ワイン=葡萄酒、コカ・コーラ/コーラ=可口可樂、オレンジジュース=柳橙汁、お茶=綠茶、ウーロン茶=烏龍茶、コーヒー=咖啡、牛乳/ミルク=牛奶、お冷=冰水（免費，不列入）

【零食・加工食品】
ガーナミルク=迦納牛奶巧克力、ナッツバー=堅果棒、ピスタチオ=開心果、プリン=布丁、ヨーグルト=優格、チーズ=起司、アイス=冰淇淋、ポテトチップス=洋芋片、スイートコーン=甜玉米、パン=麵包、クッキー=餅乾

【藥妝・日用品】
シャンプー=洗髮精、リンス/コンディショナー=潤髮乳、ボディソープ=沐浴乳、歯ブラシ=牙刷、歯磨き粉=牙膏、洗顔料=洗面乳、化粧水=化妝水、乳液=乳液、日焼け止め=防曬乳、マスク=口罩、絆創膏=OK繃、胃薬=胃藥、解熱剤=退燒藥、電池=電池、傘=雨傘

【分類判斷】根據店家類型與品項，從以下選一個最符合的分類：
- 餐飲：餐廳、居酒屋、咖啡廳、速食、拉麵店、壽司店、便利商店熟食
- 超市：超市、生鮮市場（如イオン、ライフ、西友、マルエツ、とうきゅう等）
- 購物：百貨、服飾、電器、便利商店日用品、雜貨
- 交通：電車、巴士、計程車、停車場、高速公路
- 住宿：飯店、旅館、民宿
- 門票：主題樂園、博物館、景點、溫泉
- 藥品：藥妝店、藥局
- 其他：無法歸類者

【稅制判斷 - 非常重要】
先判斷收據是「外税」還是「内税」：
- 外税：品項金額為稅前，稅金另外列出後加到合計（如 外税8% ¥258）→ tax_included=false
  - price 填稅前單價，驗算：sum(price×qty) - discount = subtotal（小計）
- 内税：品項金額已含稅，標示「内消費税等」「税込」或免税（Tax Free, 消費税等¥0）→ tax_included=true
  - price 填含稅單價（如收據上標示的價格），驗算：sum(price×qty) - discount = total（合計）

【price 欄位規則 - 最重要】
- price 永遠填「單品單價」，不是行小計（合計金額÷數量）
- 「単450× 2個 ¥900」→ price:450, quantity:2（単価450，数量2，行合計900）
- 「2コ×単299 ¥598」→ price:299, quantity:2
- 「¥300」（數量=1）→ price:300, quantity:1
- 確認：price × quantity = 該行的行合計金額

【折扣/值引き - 收據下方必須辨識】
務必掃描收據下半段，找出所有折扣並加總到 discount：
- クーポン割引（優惠券）：如「クーポン割引 5% -¥597」
- まとめ値引き（整批折扣）：如「Cスニーカーゴム -¥198」
- ポイント割引、サービス料割引、会員割引 等
- 所有 -¥XX 形式的折扣金額全部加總後填入 discount

【免税（Tax Free）辨識】
- 若收據顯示「免税」「Tax Free」「(消費税等 ¥0)」→ tax_included=true，tax=0
- 免税額（Tax exemption ¥XXX）是給顧客的退稅資訊，不是稅金，不要填入 tax

【金額欄位說明】
- tax_included = true（内税或免税）或 false（外税）
- subtotal = 外税時稅前小計；内税/免税時省略或填 0
- discount = 所有折扣/値引き合計（無則填 0）
- tax = 稅金（外税填外加稅額；内税填内含稅額；免税填 0）
- total = 合計（實際付款金額）
- 驗算：sum(price×qty) - discount + tax(外税時) = total

【付款方式辨識】
掃描收據下方的付款欄位，判斷付款方式填入 payment：
- "現金" → payment:"現金"（有「現金お預り」「お釣り」等字樣）
- "信用卡" → payment:"信用卡"（クレジット、VISA、Master、JCB、AMEX、CCTクレジット等）
- "PayPay" → payment:"PayPay"
- "Suica" → payment:"Suica"（Suica、交通系IC、ICOCA等）
- "iD" → payment:"iD"（iD、QUICPay等電子錢包）
- 無法判斷 → payment:"現金"（預設）

【輸出格式】只回傳 JSON，不要任何說明文字或 markdown 符號：
{"store_name_zh":"店名（繁體中文）","store_name_ja":"店名（日文原文）","date":"YYYY-MM-DD","category":"餐飲或超市或購物或交通或住宿或門票或藥品或其他","tax_included":true或false,"payment":"現金或信用卡或PayPay或Suica或iD","items":[{"name_zh":"品項繁中譯名","name_ja":"日文原文","price":單品單價數字,"quantity":數量數字,"tax_rate":8或10}],"subtotal":小計數字,"discount":折扣合計數字,"tax":稅金數字,"total":含稅合計數字}`;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) return json({ error: "伺服器尚未設定 ANTHROPIC_API_KEY" }, 500);

    // ── 身分檢查：必須是登入者，且至少屬於一個旅程 ──
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader) return json({ error: "請先登入再使用掃描" }, 401);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user }, error: authErr } = await supabase.auth.getUser();
    if (authErr || !user) return json({ error: "登入狀態已失效，請重新登入" }, 401);

    const { data: trips, error: tripErr } = await supabase
      .from("user_trips").select("trip_id").limit(1);
    if (tripErr) return json({ error: "無法確認旅程資格：" + tripErr.message }, 403);
    if (!trips || trips.length === 0) {
      return json({ error: "請先加入旅程才能使用掃描" }, 403);
    }

    // ── 取得圖片 ──
    const { image, media_type } = await req.json();
    if (!image) return json({ error: "沒有收到圖片" }, 400);
    const bytes = Math.round(image.length * 0.75);
    if (bytes > MAX_IMAGE_BYTES) {
      return json({ error: `圖片過大（${Math.round(bytes / 1024)}KB），請重新拍攝` }, 413);
    }

    // ── 呼叫 Anthropic ──
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 3000,
        thinking: { type: "disabled" },
        output_config: { effort: "low" },
        messages: [{
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: media_type || "image/jpeg", data: image } },
            { type: "text", text: RECEIPT_PROMPT },
          ],
        }],
      }),
    });

    const data = await resp.json();
    if (data.error) return json({ error: data.error.message }, 502);
    if (data.stop_reason === "max_tokens") {
      return json({ error: "收據品項太多，辨識結果被截斷，請分次拍攝" }, 502);
    }

    const text = data.content?.find((c: { type: string }) => c.type === "text")?.text ?? "";
    let parsed;
    try {
      parsed = JSON.parse(text.replace(/```json|```/g, "").trim());
    } catch {
      return json({ error: "辨識結果格式異常，請再試一次" }, 502);
    }

    return json({ receipt: parsed, usage: data.usage });
  } catch (e) {
    return json({ error: "辨識失敗：" + (e instanceof Error ? e.message : String(e)) }, 500);
  }
});
