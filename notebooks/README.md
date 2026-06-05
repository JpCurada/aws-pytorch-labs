# Cross-Lingual Knowledge Distillation for Low-Resource Filipino Sentiment Analysis

> **John Paul Curada, Marie Criz Zaragoza, and Neo Geroda**

A knowledge-distillation pipeline that compresses a large multilingual transformer into a smaller, faster student model for **Filipino sentiment analysis**, while retaining most of the teacher's accuracy. Built for deployment on resource-constrained devices.

---

## Project Goal

Develop an efficient Filipino sentiment analysis model through **knowledge distillation** that balances three competing objectives: high accuracy, fast inference, and small model size. We leverage a large multilingual **teacher** model to train a smaller, efficient **student** model suitable for resource-constrained devices, while maintaining acceptable performance on low-resource Filipino-language data.

---

## Results at a Glance

| Metric            | Teacher (XLM-RoBERTa) | Student (DistilBERT) | Change          |
| ----------------- | --------------------- | -------------------- | --------------- |
| Accuracy          | 84.85%                | 77.78%               | −7.07%          |
| Precision         | 84.62%                | 82.95%               | −1.67%          |
| Recall            | 86.27%                | 71.57%               | −14.70%         |
| F1-Score          | 85.44%                | 76.84%               | −8.60%          |
| Inference Time¹   | 0.764 s               | 0.406 s              | **1.88× faster** |
| Parameters        | 559M                  | 335M                 | **40% smaller** |
| Knowledge Retained| 100%                  | **91.6%**            | —               |

<sub>¹ Wall-clock time to score the 198-sample held-out test set.</sub>

The student retains **91.6% of the teacher's accuracy** while running nearly **2× faster** and using **40% fewer parameters** — an acceptable trade-off for deployment-focused applications.

---

## Methodology

### Phase 1 — Data Preparation

- Collected **1,000 Lazada product reviews** and derived binary sentiment labels from star ratings (`rating ≤ 3` → negative, `rating > 3` → positive).
- Removed **211 empty reviews**, leaving **789** usable samples.
- Stratified split into **train (60%, 593)**, **validation (20%, 198)**, and **test (20%, 198)** to preserve class balance across subsets.
- Tokenized every review to **128-token** sequences using the XLM-RoBERTa tokenizer.

### Phase 2 — Teacher Model Development

- **Architecture:** XLM-RoBERTa-Base — 12 transformer layers, 768 hidden dim, 250K vocabulary, 559M parameters.
- Fine-tuned on **hard labels** for **10 epochs** with cross-entropy loss, AdamW (`lr = 1e-5`), batch size 8.
- **Test results:** 84.85% accuracy · 84.62% precision · 86.27% recall · 85.44% F1.
- Inference: **0.764 s** over the 198-sample test set.

### Phase 3 — Soft Target Generation

- Ran the trained teacher over **all splits** to extract per-sample probability distributions (*soft targets*).
- Soft targets encode the teacher's **decision confidence and learned boundaries** — strictly more informative than hard labels for distillation.
- Saved as NumPy arrays (`soft_targets_{train,val,test}.npy`) for student training.

### Phase 4 — Student Model Development (Dual-Loss Distillation)

- **Architecture:** DistilBERT-Base-Multilingual — 6 transformer layers, 335M parameters (40% smaller than the teacher).
- Resized the embedding table to the shared **XLM-RoBERTa vocabulary (250,002 tokens)** so teacher soft targets align with student logits.
- **Dual-loss objective** with temperature softening:

  ```
  loss = α · KL(student ‖ teacher) + (1 − α) · CrossEntropy(student, hard_labels)
  where  α = 0.6,  temperature T = 2.0
  ```

  → 60% distillation (KL divergence) + 40% supervised (cross-entropy).
- Trained for **15 epochs** with AdamW (`lr = 3e-5`), batch size 8.

### Phase 5 — Evaluation & Comparison

- Evaluated both models on the **held-out test set**, computing accuracy, precision, recall, and F1.
- Measured wall-clock inference time to quantify the practical efficiency gain.
- See the [Results at a Glance](#results-at-a-glance) table for the full comparison.

### Phase 6 — Model Persistence

- Exported **both** teacher and student models with their tokenizers in standard **HuggingFace format**.
- Provided reusable `predict_sentiment(...)` inference functions for scoring new Filipino reviews with confidence scores.

---

## Key Takeaways

- **Dual-loss distillation works for low-resource languages.** Combining KL divergence with cross-entropy lets the student learn both the teacher's soft knowledge and the ground-truth signal.
- **Temperature scaling (T = 2.0)** softens soft targets enough for smooth knowledge transfer.
- **Strong compression with graceful degradation:** 91.6% accuracy retention at 40% fewer parameters and 1.88× speedup.
- **Where the student struggles:** complex linguistic phenomena such as **negation and sarcasm** — a direct consequence of reduced model capacity. Recall drops more than precision (−14.7% vs −1.7%), meaning the student misses more true positives but stays confident when it does predict positive.

---

## Repository Layout

```
notebooks/
├── cdlk-filipino-sentiment.ipynb   # End-to-end pipeline (data → teacher → distill → eval)
└── README.md                       # This file

models/
├── teacher_model/                  # XLM-RoBERTa-Base (HuggingFace format)
├── student_model/                  # DistilBERT-Base-Multilingual (distilled)
├── soft_targets_train.npy          # Teacher soft targets — train split
├── soft_targets_val.npy            # Teacher soft targets — validation split
├── soft_targets_test.npy           # Teacher soft targets — test split
├── model_evaluation_comprehensive.png   # Static evaluation charts
└── model_evaluation_interactive.html    # Interactive Plotly evaluation report
```

---

## Reproducing the Work

The notebook was developed on **Kaggle** (GPU runtime) and expects the Lazada reviews dataset mounted at `/kaggle/input/lazada-reviews/reviews.json`.

```bash
pip install keras-hub keras kagglehub transformers torch scikit-learn plotly
```

Then run `cdlk-filipino-sentiment.ipynb` top to bottom. Each step is annotated with markdown describing **what** it does and **why**.

---

## Current Status

The knowledge-distillation pipeline is **complete and functional**, from data preparation through evaluation. Both teacher and student models are trained and exported in HuggingFace format.

**Next step:** UI development for interactive sentiment prediction.

---

## Where this fits

- **Input:** the raw dataset described in [`../data/README.md`](../data/README.md).
- **Output:** the trained `teacher_model/` and `student_model/` in `../models/`.
- **Next:** those models are served by the API in [`../api/README.md`](../api/README.md).

See the [project README](../README.md) for the full setup and deployment guide.
