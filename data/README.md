# Data

This folder holds the raw dataset used to train the sentiment models.

## `reviews.json`

About 1,000 product reviews scraped from Lazada (a Southeast Asian e-commerce
platform). The reviews are written in Filipino, often mixed with English and
informal spelling.

### Format

A JSON array of objects. Each object has two fields:

```json
[
  { "review": "sir okay armygreen shorts nice ", "rating": 5 },
  { "review": "ang pangit ng quality sayang pera", "rating": 1 }
]
```

| Field | Type | Description |
| --- | --- | --- |
| `review` | string | The review text written by the customer |
| `rating` | integer | Star rating from 1 to 5 |

### From ratings to sentiment labels

The dataset does not contain sentiment labels directly. They are derived from the
star rating during training (see [`notebooks/`](../notebooks/)):

- `rating <= 3` is treated as **negative** (label `0`)
- `rating > 3` is treated as **positive** (label `1`)

This binary rule keeps the task simple and is a common starting point for
review-based sentiment analysis.

### Cleaning

Reviews with an empty `review` field are removed before training. In the notebook
this dropped 211 rows, leaving 789 usable reviews, which are then split into
training (60%), validation (20%), and test (20%) sets.

## How it is used

The training notebook reads this file, applies the labeling and cleaning rules
above, tokenizes the text, and uses it to train the teacher model and then
distill the student model. See [`notebooks/README.md`](../notebooks/README.md)
for the full pipeline.
