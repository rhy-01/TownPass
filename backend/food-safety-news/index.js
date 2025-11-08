import express from "express";
import Parser from "rss-parser";

const app = express();

const parser = new Parser({
  timeout: 10000,
  headers: {
    "User-Agent": "Mozilla/5.0 (compatible; FoodNewsBot/1.0)"
  }
});

const FEED_URL = "https://www.fda.gov.tw/tc/rssNews.ashx";

async function fetchFoodSafetyNews() {
  try {
    console.log("Fetching:", FEED_URL);

    const feed = await parser.parseURL(FEED_URL);

    const items = feed.items.map(item => ({
      title: item.title,
      summary: item.contentSnippet || "",
      link: item.link,
      pubDate: new Date(item.pubDate || item.isoDate || Date.now())
    }));

    // 排序後取最新 10 則
    items.sort((a, b) => b.pubDate - a.pubDate);

    return items.slice(0, 10);

  } catch (err) {
    console.error("RSS fetch failed:", err.message);
    return [];
  }
}

app.get("/foodnews", async (req, res) => {
  try {
    const result = await fetchFoodSafetyNews();
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: "Failed to fetch food safety news" });
  }
});

app.listen(3000, () => {
  console.log("FoodNews service running at http://localhost:3000/foodnews");
});
