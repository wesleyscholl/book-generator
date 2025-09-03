#!/usr/bin/env python3

import requests
import json
import sys
import time
import re
import csv
from urllib.parse import quote_plus, urlencode
from bs4 import BeautifulSoup
import random
from datetime import datetime, timedelta
from collections import Counter, defaultdict
import statistics

class MarketResearcher:
    def __init__(self, config=None):
        self.session = requests.Session()
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept-Language': 'en-US,en;q=0.9',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
        }
        self.session.headers.update(self.headers)
        self.config = config or {}
        self.rate_limit_delay = 2

    def search_amazon_comprehensive(self, query, max_results=50):
        """Comprehensive Amazon search with detailed metrics"""
        print(f"🔍 Searching Amazon for: '{query}'")
        
        books = []
        page = 1
        
        while len(books) < max_results and page <= 5:
            url = f"https://www.amazon.com/s?k={quote_plus(query)}&i=stripbooks&page={page}"
            
            try:
                time.sleep(self.rate_limit_delay)
                response = self.session.get(url, timeout=15, verify=False)
                response.raise_for_status()
                soup = BeautifulSoup(response.content, 'html.parser')
                
                results = soup.find_all('div', {'data-component-type': 's-search-result'})
                
                if not results:
                    break
                
                for result in results:
                    if len(books) >= max_results:
                        break
                    
                    book = self.extract_comprehensive_book_data(result, query)
                    if book:
                        books.append(book)
                
                page += 1
                
            except Exception as e:
                print(f"Error on page {page}: {e}")
                break
        
        return books

    def extract_comprehensive_book_data(self, result_div, search_query):
        """Extract comprehensive book data"""
        try:
            # Basic info
            title_elem = result_div.find('h2', class_='a-size-mini')
            if not title_elem:
                title_elem = result_div.find('span', class_='a-size-medium')
            title = title_elem.get_text().strip() if title_elem else "Unknown"

            # Author
            author_elem = result_div.find('a', class_='a-link-normal')
            if not author_elem:
                author_elem = result_div.find('span', class_='a-size-base')
            author = author_elem.get_text().strip() if author_elem else "Unknown"

            # Reviews and rating
            reviews_elem = result_div.find('span', class_='a-size-base')
            reviews_text = reviews_elem.get_text() if reviews_elem else "0"
            reviews_count = self.extract_number(reviews_text)

            rating_elem = result_div.find('span', class_='a-icon-alt')
            rating_text = rating_elem.get_text() if rating_elem else "0 out of 5 stars"
            rating = self.extract_rating(rating_text)

            # Price analysis
            price_elem = result_div.find('span', class_='a-price-whole')
            if not price_elem:
                price_elem = result_div.find('span', class_='a-offscreen')
            
            price_str = price_elem.get_text().strip() if price_elem else "0"
            price = self.extract_price(price_str)

            # ASIN
            asin = result_div.get('data-asin', 'Unknown')

            # Publication estimation (from result context)
            pub_date = self.estimate_publication_date(result_div)

            return {
                'title': title,
                'author': author,
                'reviews_count': reviews_count,
                'rating': rating,
                'price': price,
                'asin': asin,
                'publication_date': pub_date,
                'search_query': search_query,
                'extracted_at': datetime.now().isoformat()
            }

        except Exception as e:
            print(f"Error extracting book data: {e}")
            return None

    def get_detailed_book_metrics(self, asin):
        """Get detailed metrics for specific book"""
        if asin == 'Unknown':
            return {}
            
        url = f"https://www.amazon.com/dp/{asin}"
        
        try:
            time.sleep(random.uniform(2, 4))
            response = self.session.get(url, timeout=15)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')
            
            details = {}
            
            # Best Seller Rank
            bsr_elem = soup.find('span', string=re.compile(r'Best Sellers Rank|Amazon Best Sellers Rank'))
            if bsr_elem:
                bsr_parent = bsr_elem.find_parent()
                if bsr_parent:
                    bsr_text = bsr_parent.get_text()
                    bsr_match = re.search(r'#([\d,]+)', bsr_text)
                    details['bsr'] = int(bsr_match.group(1).replace(',', '')) if bsr_match else None
                    
                    # Extract categories
                    categories = re.findall(r'in\s+([^(]+)(?:\s+\([^)]+\))?', bsr_text)
                    details['categories'] = [cat.strip() for cat in categories[:3]]

            # Page count
            pages_elem = soup.find('span', string=re.compile(r'Print length|File Size'))
            if pages_elem:
                pages_text = pages_elem.find_next().get_text()
                pages_match = re.search(r'(\d+)', pages_text)
                details['pages'] = int(pages_match.group(1)) if pages_match else None

            # Publication date
            pub_elem = soup.find('span', string=re.compile(r'Publication date'))
            if pub_elem:
                details['publication_date'] = pub_elem.find_next().get_text().strip()

            # Description length (content analysis)
            desc_elem = soup.find('div', id='bookDescription_feature_div')
            if desc_elem:
                desc_text = desc_elem.get_text()
                details['description_length'] = len(desc_text.strip())
                details['description_quality'] = self.analyze_description_quality(desc_text)

            return details

        except Exception as e:
            print(f"Error getting detailed metrics for {asin}: {e}")
            return {}

    def analyze_market_opportunity(self, books, query):
        """Comprehensive market opportunity analysis"""
        if not books:
            return {}

        analysis = {
            'query': query,
            'total_books_analyzed': len(books),
            'analysis_date': datetime.now().isoformat()
        }

        # Competition Analysis
        analysis['competition'] = self.analyze_competition(books)
        
        # Demand Analysis  
        analysis['demand'] = self.analyze_demand(books, query)
        
        # Quality Gap Analysis
        analysis['quality_gaps'] = self.analyze_quality_gaps(books)
        
        # Price Analysis
        analysis['pricing'] = self.analyze_pricing(books)
        
        # Market Timing
        analysis['timing'] = self.analyze_market_timing(books)
        
        # Overall Opportunity Score
        analysis['opportunity_score'] = self.calculate_opportunity_score(analysis)
        
        return analysis

    def analyze_competition(self, books):
        """Analyze competitive landscape"""
        valid_books = [b for b in books if b.get('reviews_count', 0) > 0]
        
        if not valid_books:
            return {'error': 'No valid books for analysis'}

        reviews = [b['reviews_count'] for b in valid_books]
        ratings = [b['rating'] for b in valid_books if b.get('rating', 0) > 0]
        
        # Author diversity
        authors = [b.get('author', 'Unknown') for b in valid_books]
        author_counts = Counter(authors)
        
        return {
            'total_competitors': len(valid_books),
            'avg_reviews': statistics.mean(reviews),
            'median_reviews': statistics.median(reviews),
            'max_reviews': max(reviews),
            'min_reviews': min(reviews),
            'avg_rating': statistics.mean(ratings) if ratings else 0,
            'author_diversity': len(set(authors)),
            'dominant_authors': dict(author_counts.most_common(5)),
            'competition_level': self.assess_competition_level(reviews, ratings)
        }

    def analyze_demand(self, books, query):
        """Analyze market demand indicators"""
        total_reviews = sum(b.get('reviews_count', 0) for b in books)
        
        # Estimate search volume from results
        result_density = len(books)
        
        # Recent activity (books with reviews in estimated recent period)
        recent_books = [b for b in books if b.get('reviews_count', 0) > 50]
        
        return {
            'total_market_reviews': total_reviews,
            'avg_reviews_per_book': total_reviews / len(books) if books else 0,
            'result_density': result_density,
            'active_books': len(recent_books),
            'market_activity_level': self.assess_market_activity(total_reviews, len(books)),
            'estimated_monthly_searches': self.estimate_search_volume(query, result_density)
        }

    def analyze_quality_gaps(self, books):
        """Identify quality opportunities"""
        gaps = {}
        
        # Rating gaps
        low_rated = [b for b in books if b.get('rating', 5) < 4.0 and b.get('reviews_count', 0) > 20]
        gaps['low_rated_opportunities'] = len(low_rated)
        
        # Format gaps
        title_words = []
        for book in books:
            title_words.extend(book.get('title', '').lower().split())
        
        word_freq = Counter(title_words)
        common_formats = ['guide', 'handbook', 'workbook', 'journal', 'planner']
        missing_formats = [fmt for fmt in common_formats if fmt not in word_freq]
        
        gaps['missing_formats'] = missing_formats
        gaps['oversaturated_formats'] = [word for word, count in word_freq.most_common(5) if count > len(books) * 0.3]
        
        return gaps

    def analyze_pricing(self, books):
        """Analyze pricing opportunities"""
        prices = [b.get('price', 0) for b in books if b.get('price', 0) > 0]
        
        if not prices:
            return {'error': 'No pricing data available'}

        price_ranges = {
            'under_3': len([p for p in prices if p < 3]),
            '3_to_6': len([p for p in prices if 3 <= p < 6]),
            '6_to_10': len([p for p in prices if 6 <= p < 10]),
            'over_10': len([p for p in prices if p >= 10])
        }

        return {
            'avg_price': statistics.mean(prices),
            'median_price': statistics.median(prices),
            'price_range_distribution': price_ranges,
            'optimal_price_gap': self.find_price_gaps(prices),
            'pricing_strategy': self.suggest_pricing_strategy(prices)
        }

    def analyze_market_timing(self, books):
        """Analyze market timing and trends"""
        # Publication date analysis
        current_year = datetime.now().year
        recent_books = []
        
        for book in books:
            pub_date = book.get('publication_date', '')
            if pub_date:
                # Simple year extraction
                year_match = re.search(r'20\d{2}', str(pub_date))
                if year_match:
                    year = int(year_match.group())
                    if year >= current_year - 2:
                        recent_books.append(book)

        return {
            'recent_publications': len(recent_books),
            'market_freshness': len(recent_books) / len(books) if books else 0,
            'publishing_trend': 'growing' if len(recent_books) > len(books) * 0.4 else 'stable',
            'opportunity_timing': 'good' if len(recent_books) < len(books) * 0.6 else 'competitive'
        }

    def calculate_opportunity_score(self, analysis):
        """Calculate overall opportunity score (0-100)"""
        score = 0
        max_score = 100

        # Competition score (30 points)
        comp = analysis.get('competition', {})
        if comp.get('competition_level') == 'low':
            score += 25
        elif comp.get('competition_level') == 'medium':
            score += 15
        else:
            score += 5

        # Demand score (40 points)  
        demand = analysis.get('demand', {})
        activity = demand.get('market_activity_level', 'low')
        if activity == 'high':
            score += 35
        elif activity == 'medium':
            score += 25
        else:
            score += 10

        # Quality gaps (20 points)
        gaps = analysis.get('quality_gaps', {})
        if gaps.get('low_rated_opportunities', 0) > 3:
            score += 15
        if gaps.get('missing_formats'):
            score += 5

        # Timing (10 points)
        timing = analysis.get('timing', {})
        if timing.get('opportunity_timing') == 'good':
            score += 8
        elif timing.get('opportunity_timing') == 'competitive':
            score += 4

        return min(score, max_score)

    # Helper methods
    def extract_number(self, text):
        numbers = re.findall(r'[\d,]+', text.replace(',', ''))
        return int(numbers[0]) if numbers else 0

    def extract_rating(self, text):
        rating_match = re.search(r'(\d+\.?\d*)', text)
        return float(rating_match.group(1)) if rating_match else 0.0

    def extract_price(self, text):
        price_match = re.search(r'\$?(\d+\.?\d*)', text.replace(',', ''))
        return float(price_match.group(1)) if price_match else 0.0

    def estimate_publication_date(self, result_div):
        # Try to find publication indicators in the result
        date_text = result_div.get_text()
        year_matches = re.findall(r'20\d{2}', date_text)
        return year_matches[-1] if year_matches else 'Unknown'

    def analyze_description_quality(self, text):
        word_count = len(text.split())
        if word_count < 50:
            return 'poor'
        elif word_count < 150:
            return 'average'
        else:
            return 'good'

    def assess_competition_level(self, reviews, ratings):
        avg_reviews = statistics.mean(reviews) if reviews else 0
        avg_rating = statistics.mean(ratings) if ratings else 0
        
        if avg_reviews > 500 and avg_rating > 4.3:
            return 'high'
        elif avg_reviews > 100 and avg_rating > 4.0:
            return 'medium'
        else:
            return 'low'

    def assess_market_activity(self, total_reviews, book_count):
        avg_reviews = total_reviews / book_count if book_count else 0
        
        # Lower thresholds to be more realistic for book markets
        if avg_reviews > 50:  # Was 200
            return 'high'
        elif avg_reviews > 15:  # Was 50
            return 'medium'
        else:
            return 'low'

    def estimate_search_volume(self, query, result_density):
        # Simple estimation based on result density
        base_estimate = result_density * 100
        
        # Adjust for query characteristics
        if len(query.split()) == 1:
            base_estimate *= 2
        elif 'how to' in query.lower():
            base_estimate *= 1.5
        
        return base_estimate

    def find_price_gaps(self, prices):
        sorted_prices = sorted(prices)
        gaps = []
        
        for i in range(len(sorted_prices) - 1):
            gap = sorted_prices[i + 1] - sorted_prices[i]
            if gap > 1.0:  # Significant price gap
                gaps.append({
                    'gap_start': sorted_prices[i],
                    'gap_end': sorted_prices[i + 1],
                    'gap_size': gap
                })
        
        return gaps

    def suggest_pricing_strategy(self, prices):
        median_price = statistics.median(prices)
        
        if median_price < 3:
            return 'premium_opportunity'
        elif median_price > 8:
            return 'budget_opportunity'
        else:
            return 'competitive_pricing'

# Additional analysis functions
def analyze_social_trends(query):
    """Analyze social media trends (simplified version)"""
    # This would need API access for real implementation
    # For now, provide structure for manual research
    return {
        'instagram_research': f"Search hashtag #{query.replace(' ', '')}",
        'tiktok_research': f"Check TikTok for #{query.replace(' ', '')}",
        'youtube_research': f"Search YouTube for '{query} tutorial'",
        'reddit_research': f"Search Reddit for r/{query.replace(' ', '')}"
    }

def generate_keyword_suggestions(successful_titles):
    """Generate keyword suggestions from successful titles"""
    all_words = []
    
    for title in successful_titles:
        words = re.findall(r'\b[a-zA-Z]{3,}\b', title.lower())
        # Filter out common words
        filtered_words = [w for w in words if w not in ['the', 'and', 'for', 'with', 'your', 'how', 'guide', 'book', 'complete', 'ultimate']]
        all_words.extend(filtered_words)
    
    word_freq = Counter(all_words)
    return word_freq.most_common(20)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 market_analyzer.py <command> <query> [options]")
        print("Commands: search, analyze, trends")
        sys.exit(1)
    
    command = sys.argv[1]
    query = sys.argv[2]
    
    researcher = MarketResearcher()
    
    if command == "search":
        max_results = int(sys.argv[3]) if len(sys.argv) > 3 else 30
        books = researcher.search_amazon_comprehensive(query, max_results)
        
        # Get detailed metrics for top books
        print(f"📊 Getting detailed metrics for {len(books)} books...")
        for book in books[:20]:  # Limit detailed analysis to prevent rate limiting
            details = researcher.get_detailed_book_metrics(book.get('asin', ''))
            book.update(details)
        
        # Save results
        with open('market_results.json', 'w') as f:
            json.dump(books, f, indent=2)
        
        # Perform analysis
        analysis = researcher.analyze_market_opportunity(books, query)
        
        # Save analysis
        with open('market_analysis.json', 'w') as f:
            json.dump(analysis, f, indent=2)
        
        print(json.dumps(analysis, indent=2))
    
    elif command == "analyze":
        # Load existing results
        try:
            with open('market_results.json', 'r') as f:
                books = json.load(f)
            
            analysis = researcher.analyze_market_opportunity(books, query)
            print(json.dumps(analysis, indent=2))
            
        except FileNotFoundError:
            print("No market results found. Run search first.")
    
    elif command == "trends":
        social_analysis = analyze_social_trends(query)
        print(json.dumps(social_analysis, indent=2))
