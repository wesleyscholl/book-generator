#!/bin/bash

# Advanced Book Market Research Script with Comprehensive Analytics
# Uses only free/open source tools for complete market analysis

set -e

# Configuration
CONFIG_FILE="$HOME/.book_research_config"
DATA_DIR="$HOME/.book_research_data"
CACHE_DIR="$DATA_DIR/cache"
RESULTS_FILE="$DATA_DIR/market_analysis.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Create directories
mkdir -p "$DATA_DIR" "$CACHE_DIR" "$DATA_DIR/reports"

# Initialize configuration
init_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'EOF'
# Book Market Research Configuration

# Amazon Analysis
MIN_REVIEWS=20
MAX_REVIEWS=1000
TARGET_BSR_MIN=5000
TARGET_BSR_MAX=100000
OPTIMAL_PRICE_MIN=2.99
OPTIMAL_PRICE_MAX=9.99

# Competition Analysis
MAX_CATEGORY_SIZE=200
MIN_CATEGORY_SIZE=20
TARGET_AVG_RATING=4.0

# Trend Analysis
TREND_LOOKBACK_MONTHS=12
MIN_TREND_SCORE=40

# Social Media Thresholds
MIN_INSTAGRAM_POSTS=1000
MIN_TIKTOK_VIEWS=100000
MIN_YOUTUBE_RESULTS=500

# Market Opportunity Scoring
COMPETITION_WEIGHT=0.3
DEMAND_WEIGHT=0.4
TREND_WEIGHT=0.2
QUALITY_GAP_WEIGHT=0.1

# Rate Limiting
SEARCH_DELAY=3
MAX_REQUESTS_PER_HOUR=60
EOF
        echo -e "${GREEN}Configuration file created at: $CONFIG_FILE${NC}"
    fi
    source "$CONFIG_FILE"
}

# Load configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        echo -e "${YELLOW}No config file found. Run 'init' first.${NC}"
        exit 1
    fi
}

# Create comprehensive market research suite
create_research_suite() {
    # Main market analyzer
    cat > "$DATA_DIR/market_analyzer.py" << 'EOF'
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
                response = self.session.get(url, timeout=15)
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
        
        if avg_reviews > 200:
            return 'high'
        elif avg_reviews > 50:
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
EOF

    chmod +x "$DATA_DIR/market_analyzer.py"

    # Google Trends analyzer (free alternative using search data)
    cat > "$DATA_DIR/trends_analyzer.py" << 'EOF'
#!/usr/bin/env python3

import requests
import json
import sys
import re
from bs4 import BeautifulSoup
import time
from urllib.parse import quote_plus
from datetime import datetime, timedelta

def analyze_google_search_trends(query):
    """
    Analyze trends using Google search results and related searches
    This is a free alternative to Google Trends API
    """
    
    # Search Google for the query and analyze result characteristics
    search_url = f"https://www.google.com/search?q={quote_plus(query)}"
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    }
    
    try:
        response = requests.get(search_url, headers=headers, timeout=10)
        soup = BeautifulSoup(response.content, 'html.parser')
        
        # Count results
        results_text = soup.find('div', id='result-stats')
        result_count = 0
        if results_text:
            count_match = re.search(r'About ([\d,]+)', results_text.get_text())
            if count_match:
                result_count = int(count_match.group(1).replace(',', ''))
        
        # Look for "People also ask" - indicates active searches
        people_ask = soup.find_all('div', class_='related-question-pair')
        related_questions = len(people_ask)
        
        # Look for recent results
        recent_indicators = len(soup.find_all(text=re.compile(r'hours ago|days ago|week ago')))
        
        # Analyze search suggestions (related searches)
        related_searches = []
        related_section = soup.find('div', {'data-async-context': 'async_id:rso;'})
        if related_section:
            links = related_section.find_all('a')
            for link in links[:10]:
                if link.get_text():
                    related_searches.append(link.get_text().strip())
        
        return {
            'query': query,
            'total_results': result_count,
            'related_questions': related_questions,
            'recent_content_indicators': recent_indicators,
            'related_searches': related_searches[:5],
            'trend_score': calculate_trend_score(result_count, related_questions, recent_indicators),
            'analysis_date': datetime.now().isoformat()
        }
    
    except Exception as e:
        print(f"Error analyzing trends for {query}: {e}")
        return None

def calculate_trend_score(result_count, related_questions, recent_indicators):
    """Calculate a trend score based on available indicators"""
    score = 0
    
    # More results generally indicate more interest
    if result_count > 1000000:
        score += 30
    elif result_count > 100000:
        score += 20
    else:
        score += 10
    
    # Related questions indicate active searches
    score += min(related_questions * 10, 30)
    
    # Recent content indicates growing interest
    score += min(recent_indicators * 5, 20)
    
    return min(score, 100)

def analyze_youtube_trends(query):
    """Analyze YouTube search results for trend indicators"""
    search_url = f"https://www.youtube.com/results?search_query={quote_plus(query)}"
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    }
    
    try:
        response = requests.get(search_url, headers=headers, timeout=10)
        
        # Count video results (simplified)
        video_count = response.text.count('videoRenderer')
        recent_videos = response.text.count('day ago') + response.text.count('days ago')
        
        return {
            'estimated_video_count': video_count,
            'recent_videos': recent_videos,
            'youtube_interest_level': 'high' if video_count > 20 else 'medium' if video_count > 10 else 'low'
        }
    
    except Exception as e:
        print(f"Error analyzing YouTube trends: {e}")
        return {}

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 trends_analyzer.py <query>")
        sys.exit(1)
    
    query = sys.argv[1]
    
    google_trends = analyze_google_search_trends(query)
    youtube_trends = analyze_youtube_trends(query)
    
    combined_analysis = {
        'google_trends': google_trends,
        'youtube_trends': youtube_trends
    }
    
    print(json.dumps(combined_analysis, indent=2))
EOF

    chmod +x "$DATA_DIR/trends_analyzer.py"

    # Report generator
    cat > "$DATA_DIR/report_generator.py" << 'EOF'
#!/usr/bin/env python3

import json
import sys
from datetime import datetime
import statistics

def generate_comprehensive_report(market_file, trends_file=None):
    """Generate a comprehensive market research report"""
    
    try:
        with open(market_file, 'r') as f:
            market_data = json.load(f)
    except FileNotFoundError:
        print("Market analysis file not found")
        return
    
    trends_data = {}
    if trends_file:
        try:
            with open(trends_file, 'r') as f:
                trends_data = json.load(f)
        except FileNotFoundError:
            pass
    
    print("=" * 80)
    print(f"COMPREHENSIVE BOOK MARKET RESEARCH REPORT")
    print("=" * 80)
    print(f"Query: {market_data.get('query', 'Unknown')}")
    print(f"Analysis Date: {market_data.get('analysis_date', 'Unknown')}")
    print(f"Total Books Analyzed: {market_data.get('total_books_analyzed', 0)}")
    print()
    
    # Opportunity Score
    opp_score = market_data.get('opportunity_score', 0)
    print(f"🎯 OVERALL OPPORTUNITY SCORE: {opp_score}/100")
    
    if opp_score >= 70:
        print("   ✅ EXCELLENT OPPORTUNITY - Highly Recommended")
    elif opp_score >= 50:
        print("   ⚡ GOOD OPPORTUNITY - Recommended with Strategy")
    elif opp_score >= 30:
        print("   ⚠️  MODERATE OPPORTUNITY - Proceed with Caution")
    else:
        print("   ❌ LOW OPPORTUNITY - Not Recommended")
    print()
    
    # Competition Analysis
    comp = market_data.get('competition', {})
    print("📊 COMPETITION ANALYSIS")
    print("-" * 40)
    print(f"Total Competitors: {comp.get('total_competitors', 0)}")
    print(f"Average Reviews: {comp.get('avg_reviews', 0):,.0f}")
    print(f"Median Reviews: {comp.get('median_reviews', 0):,.0f}")
    print(f"Competition Level: {comp.get('competition_level', 'Unknown').title()}")
    print(f"Author Diversity: {comp.get('author_diversity', 0)} unique authors")
    
    dominant_authors = comp.get('dominant_authors', {})
    if dominant_authors:
        print("Top Authors by Book Count:")
        for author, count in list(dominant_authors.items())[:3]:
            print(f"  • {author}: {count} books")
    print()
    
    # Demand Analysis
    demand = market_data.get('demand', {})
    print("📈 DEMAND ANALYSIS")
    print("-" * 40)
    print(f"Total Market Reviews: {demand.get('total_market_reviews', 0):,}")
    print(f"Avg Reviews per Book: {demand.get('avg_reviews_per_book', 0):.1f}")
    print(f"Market Activity Level: {demand.get('market_activity_level', 'Unknown').title()}")
    print(f"Estimated Monthly Searches: {demand.get('estimated_monthly_searches', 0):,}")
    print()
    
    # Quality Gaps Analysis
    gaps = market_data.get('quality_gaps', {})
    print("🎯 QUALITY OPPORTUNITIES")
    print("-" * 40)
    print(f"Low-Rated Books (Under 4.0): {gaps.get('low_rated_opportunities', 0)}")
    
    missing_formats = gaps.get('missing_formats', [])
    if missing_formats:
        print("Missing Formats (Opportunities):")
        for fmt in missing_formats:
            print(f"  • {fmt.title()}")
    
    oversaturated = gaps.get('oversaturated_formats', [])
    if oversaturated:
        print("Oversaturated Formats (Avoid):")
        for fmt in oversaturated:
            print(f"  • {fmt.title()}")
    print()
    
    # Pricing Analysis
    pricing = market_data.get('pricing', {})
    if not pricing.get('error'):
        print("💰 PRICING ANALYSIS")
        print("-" * 40)
        print(f"Average Price: ${pricing.get('avg_price', 0):.2f}")
        print(f"Median Price: ${pricing.get('median_price', 0):.2f}")
        
        price_dist = pricing.get('price_range_distribution', {})
        print("Price Distribution:")
        print(f"  • Under $3: {price_dist.get('under_3', 0)} books")
        print(f"  • $3-$6: {price_dist.get('3_to_6', 0)} books")
        print(f"  • $6-$10: {price_dist.get('6_to_10', 0)} books")
        print(f"  • Over $10: {price_dist.get('over_10', 0)} books")
        
        strategy = pricing.get('pricing_strategy', '')
        print(f"Recommended Strategy: {strategy.replace('_', ' ').title()}")
        
        price_gaps = pricing.get('optimal_price_gap', [])
        if price_gaps:
            print("Price Gap Opportunities:")
            for gap in price_gaps[:3]:
                print(f"  • ${gap.get('gap_start', 0):.2f} - ${gap.get('gap_end', 0):.2f} (Gap: ${gap.get('gap_size', 0):.2f})")
        print()
    
    # Market Timing
    timing = market_data.get('timing', {})
    print("⏰ MARKET TIMING")
    print("-" * 40)
    print(f"Recent Publications: {timing.get('recent_publications', 0)}")
    print(f"Market Freshness: {timing.get('market_freshness', 0):.1%}")
    print(f"Publishing Trend: {timing.get('publishing_trend', 'Unknown').title()}")
    print(f"Opportunity Timing: {timing.get('opportunity_timing', 'Unknown').title()}")
    print()
    
    # Trends Analysis (if available)
    if trends_data:
        google_trends = trends_data.get('google_trends', {})
        youtube_trends = trends_data.get('youtube_trends', {})
        
        print("🔥 TREND ANALYSIS")
        print("-" * 40)
        if google_trends:
            print(f"Google Results: {google_trends.get('total_results', 0):,}")
            print(f"Related Questions: {google_trends.get('related_questions', 0)}")
            print(f"Trend Score: {google_trends.get('trend_score', 0)}/100")
        
        if youtube_trends:
            print(f"YouTube Interest: {youtube_trends.get('youtube_interest_level', 'Unknown').title()}")
        print()
    
    # Recommendations
    print("💡 STRATEGIC RECOMMENDATIONS")
    print("=" * 50)
    
    if opp_score >= 50:
        print("✅ PROCEED WITH THIS NICHE")
        print("Key Success Factors:")
        
        if comp.get('competition_level') == 'low':
            print("  • Low competition - great entry opportunity")
        
        if gaps.get('low_rated_opportunities', 0) > 0:
            print(f"  • {gaps['low_rated_opportunities']} poorly rated books to outcompete")
        
        if missing_formats:
            print(f"  • Missing formats to explore: {', '.join(missing_formats[:3])}")
        
        if timing.get('opportunity_timing') == 'good':
            print("  • Good timing - not oversaturated with recent releases")
            
    else:
        print("⚠️ CONSIDER ALTERNATIVE NICHES")
        print("Risk Factors:")
        
        if comp.get('competition_level') == 'high':
            print("  • High competition with established players")
        
        if demand.get('market_activity_level') == 'low':
            print("  • Low market demand indicators")
        
        if timing.get('opportunity_timing') == 'competitive':
            print("  • Market may be oversaturated")
    
    print()
    print("📋 ACTION ITEMS")
    print("-" * 20)
    print("1. Research top 5 competitors in detail")
    print("2. Analyze their reviews for improvement opportunities")  
    print("3. Consider unique angles or underserved sub-niches")
    print("4. Plan content that addresses quality gaps identified")
    print("5. Set competitive pricing based on analysis above")
    print()
    
    # Export summary data
    summary = {
        'query': market_data.get('query'),
        'opportunity_score': opp_score,
        'competition_level': comp.get('competition_level'),
        'market_activity': demand.get('market_activity_level'),
        'recommended_action': 'proceed' if opp_score >= 50 else 'reconsider',
        'key_opportunities': missing_formats,
        'avg_price': pricing.get('avg_price', 0),
        'analysis_date': datetime.now().isoformat()
    }
    
    with open('market_summary.json', 'w') as f:
        json.dump(summary, f, indent=2)
    
    print("📄 Summary saved to: market_summary.json")
    print("📊 Full analysis saved to: market_analysis.json")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 report_generator.py <market_analysis.json> [trends_analysis.json]")
        sys.exit(1)
    
    market_file = sys.argv[1]
    trends_file = sys.argv[2] if len(sys.argv) > 2 else None
    
    generate_comprehensive_report(market_file, trends_file)
EOF

    chmod +x "$DATA_DIR/report_generator.py"

    # Social media analyzer
    cat > "$DATA_DIR/social_analyzer.py" << 'EOF'
#!/usr/bin/env python3

import requests
import json
import sys
import re
from bs4 import BeautifulSoup
import time
from urllib.parse import quote_plus

def analyze_instagram_hashtags(query):
    """Analyze Instagram hashtag popularity (simplified)"""
    hashtag = query.replace(' ', '').replace('#', '')
    
    # Since Instagram API requires authentication, we'll provide research guidance
    return {
        'hashtag': f"#{hashtag}",
        'research_url': f"https://www.instagram.com/explore/tags/{hashtag}/",
        'analysis_method': 'manual',
        'research_notes': [
            "Visit the hashtag page manually",
            "Count recent posts (last 24 hours)",
            "Check engagement rates on top posts",
            "Look for business/brand usage vs personal",
            "Note related hashtags suggested"
        ]
    }

def analyze_reddit_communities(query):
    """Analyze Reddit communities for topic interest"""
    search_url = f"https://www.reddit.com/search.json?q={quote_plus(query)}&type=sr"
    
    headers = {
        'User-Agent': 'BookResearch/1.0'
    }
    
    try:
        time.sleep(2)  # Rate limiting
        response = requests.get(search_url, headers=headers, timeout=10)
        
        if response.status_code == 200:
            data = response.json()
            subreddits = []
            
            for item in data.get('data', {}).get('children', [])[:10]:
                sub_data = item.get('data', {})
                subreddits.append({
                    'name': sub_data.get('display_name', ''),
                    'subscribers': sub_data.get('subscribers', 0),
                    'description': sub_data.get('public_description', '')[:100]
                })
            
            return {
                'relevant_subreddits': subreddits,
                'total_found': len(subreddits),
                'engagement_potential': 'high' if any(s['subscribers'] > 10000 for s in subreddits) else 'medium'
            }
    except Exception as e:
        print(f"Reddit analysis error: {e}")
    
    return {'error': 'Could not analyze Reddit communities'}

def analyze_pinterest_interest(query):
    """Analyze Pinterest for topic interest"""
    # Pinterest search URL structure
    search_url = f"https://www.pinterest.com/search/pins/?q={quote_plus(query)}"
    
    return {
        'search_url': search_url,
        'research_method': 'manual',
        'analysis_steps': [
            "Visit Pinterest search manually",
            "Count pins in results",
            "Check save rates on top pins", 
            "Look for seasonal trends",
            "Note related search suggestions"
        ],
        'indicators': [
            "High saves = strong interest",
            "Many boards = topic authority potential",
            "Recent pins = trending topic",
            "Business pins = commercial opportunity"
        ]
    }

def get_social_research_checklist(query):
    """Generate comprehensive social media research checklist"""
    return {
        'query': query,
        'platforms': {
            'tiktok': {
                'hashtags_to_check': [
                    f"#{query.replace(' ', '')}",
                    f"#{query.replace(' ', '')}tips", 
                    f"#{query.replace(' ', '')}hack"
                ],
                'metrics_to_note': [
                    "Total hashtag views",
                    "Recent post count (last 7 days)",
                    "Average video engagement",
                    "Creator types (individual vs business)"
                ]
            },
            'instagram': {
                'research_areas': [
                    f"#{query.replace(' ', '')} hashtag page",
                    f"Stories mentioning {query}",
                    f"Reels with {query} audio/hashtags",
                    f"Business accounts in niche"
                ],
                'engagement_indicators': [
                    "Comments per post",
                    "Save rates",
                    "Share frequency",
                    "Story interactions"
                ]
            },
            'youtube': {
                'search_terms': [
                    f"{query} tutorial",
                    f"{query} guide", 
                    f"how to {query}",
                    f"{query} tips"
                ],
                'analysis_points': [
                    "Video count in results",
                    "View counts on top videos",
                    "Upload frequency",
                    "Channel subscriber counts"
                ]
            },
            'pinterest': {
                'board_analysis': [
                    f"Boards about {query}",
                    f"Pin save rates",
                    f"Seasonal trends",
                    f"Related topics"
                ]
            }
        }
    }

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 social_analyzer.py <query>")
        sys.exit(1)
    
    query = sys.argv[1]
    
    # Run all social media analyses
    analysis = {
        'query': query,
        'instagram': analyze_instagram_hashtags(query),
        'reddit': analyze_reddit_communities(query),
        'pinterest': analyze_pinterest_interest(query),
        'research_checklist': get_social_research_checklist(query)
    }
    
    print(json.dumps(analysis, indent=2))
EOF

    chmod +x "$DATA_DIR/social_analyzer.py"
}

# Enhanced search function with comprehensive analysis
comprehensive_search() {
    local query="$1"
    local max_results="${2:-30}"
    
    echo -e "${BLUE}🚀 Starting Comprehensive Market Research for: '$query'${NC}"
    echo -e "${YELLOW}This will take 5-10 minutes for complete analysis...${NC}"
    echo
    
    # Step 1: Amazon Market Analysis
    echo -e "${CYAN}Step 1: Amazon Market Analysis${NC}"
    python3 "$DATA_DIR/market_analyzer.py" search "$query" "$max_results"
    
    # Step 2: Trend Analysis  
    echo -e "${CYAN}Step 2: Search Trend Analysis${NC}"
    python3 "$DATA_DIR/trends_analyzer.py" "$query" > "$DATA_DIR/trends_analysis.json"
    
    # Step 3: Social Media Research Guidance
    echo -e "${CYAN}Step 3: Social Media Research Guide${NC}"
    python3 "$DATA_DIR/social_analyzer.py" "$query" > "$DATA_DIR/social_analysis.json"
    
    # Step 4: Generate Comprehensive Report
    echo -e "${CYAN}Step 4: Generating Comprehensive Report${NC}"
    python3 "$DATA_DIR/report_generator.py" "market_analysis.json" "trends_analysis.json"
    
    echo -e "${GREEN}✅ Comprehensive analysis complete!${NC}"
    echo -e "${BLUE}📋 Files generated:${NC}"
    echo "  • market_results.json - Raw book data"
    echo "  • market_analysis.json - Detailed analysis"
    echo "  • trends_analysis.json - Trend data"  
    echo "  • social_analysis.json - Social media research guide"
    echo "  • market_summary.json - Executive summary"
    
    # Show quick summary
    echo
    echo -e "${PURPLE}📊 QUICK SUMMARY${NC}"
    if [[ -f "market_summary.json" ]]; then
        python3 -c "
import json
with open('market_summary.json') as f:
    data = json.load(f)
print(f\"Opportunity Score: {data.get('opportunity_score', 0)}/100\")
print(f\"Competition: {data.get('competition_level', 'Unknown').title()}\")
print(f\"Market Activity: {data.get('market_activity', 'Unknown').title()}\")
print(f\"Recommendation: {data.get('recommended_action', 'Unknown').title()}\")
"
    fi
}

# Quick opportunity scoring
score_opportunities() {
    echo -e "${BLUE}📊 Scoring Multiple Opportunities${NC}"
    echo "Enter keywords separated by commas:"
    read -r keywords
    
    IFS=',' read -ra QUERIES <<< "$keywords"
    
    echo -e "${YELLOW}Analyzing ${#QUERIES[@]} opportunities...${NC}"
    
    > "$DATA_DIR/opportunity_scores.csv"
    echo "Query,Opportunity Score,Competition Level,Market Activity,Recommendation" >> "$DATA_DIR/opportunity_scores.csv"
    
    for query in "${QUERIES[@]}"; do
        query=$(echo "$query" | xargs)  # Trim whitespace
        echo -e "${CYAN}Analyzing: $query${NC}"
        
        python3 "$DATA_DIR/market_analyzer.py" search "$query" 20 > /dev/null 2>&1
        
        if [[ -f "market_analysis.json" ]]; then
            python3 -c "
import json
try:
    with open('market_analysis.json') as f:
        data = json.load(f)
    score = data.get('opportunity_score', 0)
    comp = data.get('competition', {}).get('competition_level', 'unknown')
    activity = data.get('demand', {}).get('market_activity_level', 'unknown')
    rec = 'proceed' if score >= 50 else 'reconsider'
    print(f'$query,{score},{comp},{activity},{rec}')
except:
    print(f'$query,0,error,error,error')
" >> "$DATA_DIR/opportunity_scores.csv"
        else
            echo "$query,0,error,error,error" >> "$DATA_DIR/opportunity_scores.csv"
        fi
        
        sleep 3  # Rate limiting
    done
    
    echo -e "${GREEN}✅ Batch analysis complete!${NC}"
    echo -e "${BLUE}Results saved to: $DATA_DIR/opportunity_scores.csv${NC}"
    
    # Show top opportunities
    echo -e "${PURPLE}🏆 TOP OPPORTUNITIES:${NC}"
    python3 -c "
import csv
opportunities = []
with open('$DATA_DIR/opportunity_scores.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        try:
            score = int(row['Opportunity Score'])
            opportunities.append((row['Query'], score, row['Competition Level'], row['Recommendation']))
        except:
            continue

opportunities.sort(key=lambda x: x[1], reverse=True)

for i, (query, score, comp, rec) in enumerate(opportunities[:5], 1):
    status = '✅' if rec == 'proceed' else '⚠️'
    print(f'{i}. {status} {query}: {score}/100 ({comp} competition)')
"
}

# Monitor trending topics
monitor_trends() {
    echo -e "${BLUE}📈 Trend Monitoring Setup${NC}"
    
    # Create monitoring script
    cat > "$DATA_DIR/trend_monitor.sh" << 'EOF'
#!/bin/bash

TRENDS_DIR="$HOME/.book_research_data/trend_monitoring"
mkdir -p "$TRENDS_DIR"

# Topics to monitor (add your own)
TOPICS=("productivity habits" "mental health" "remote work" "digital minimalism" "sustainable living")

echo "$(date): Starting trend monitoring" >> "$TRENDS_DIR/monitor.log"

for topic in "${TOPICS[@]}"; do
    echo "Monitoring: $topic"
    
    # Analyze current trends
    python3 "$HOME/.book_research_data/trends_analyzer.py" "$topic" > "$TRENDS_DIR/${topic// /_}_$(date +%Y%m%d).json"
    
    # Quick market check
    python3 "$HOME/.book_research_data/market_analyzer.py" search "$topic" 10 > /dev/null 2>&1
    
    if [[ -f "market_analysis.json" ]]; then
        mv "market_analysis.json" "$TRENDS_DIR/${topic// /_}_market_$(date +%Y%m%d).json"
    fi
    
    sleep 5
done

echo "$(date): Trend monitoring complete" >> "$TRENDS_DIR/monitor.log"
EOF

    chmod +x "$DATA_DIR/trend_monitor.sh"
    
    echo -e "${GREEN}✅ Trend monitoring script created${NC}"
    echo -e "${BLUE}Location: $DATA_DIR/trend_monitor.sh${NC}"
    echo
    echo "To run monitoring:"
    echo "  $DATA_DIR/trend_monitor.sh"
    echo
    echo "To set up daily monitoring (cron):"
    echo "  crontab -e"
    echo "  Add: 0 9 * * * $DATA_DIR/trend_monitor.sh"
}

# Export comprehensive data
export_comprehensive() {
    echo -e "${BLUE}📤 Exporting Comprehensive Data${NC}"
    
    timestamp=$(date +%Y%m%d_%H%M%S)
    export_dir="$DATA_DIR/exports/export_$timestamp"
    mkdir -p "$export_dir"
    
    # Copy all analysis files
    for file in market_*.json trends_*.json social_*.json opportunity_scores.csv; do
        if [[ -f "$file" ]]; then
            cp "$file" "$export_dir/"
        fi
    done
    
    # Create summary report
    cat > "$export_dir/README.md" << EOF
# Book Market Research Export
Generated: $(date)

## Files Included:
- market_results.json - Raw Amazon book data
- market_analysis.json - Detailed market analysis
- trends_analysis.json - Search trend analysis  
- social_analysis.json - Social media research guide
- market_summary.json - Executive summary
- opportunity_scores.csv - Batch analysis results

## Analysis Summary:
$(python3 -c "
import json
try:
    with open('market_summary.json') as f:
        data = json.load(f)
    print(f'Query: {data.get(\"query\", \"Unknown\")}')
    print(f'Opportunity Score: {data.get(\"opportunity_score\", 0)}/100')
    print(f'Competition Level: {data.get(\"competition_level\", \"Unknown\")}')
    print(f'Recommendation: {data.get(\"recommended_action\", \"Unknown\")}')
except:
    print('No summary data available')
")

## Next Steps:
1. Review opportunity scores for highest-potential niches
2. Conduct manual social media research using provided guides
3. Analyze top competitors in detail
4. Plan content strategy based on identified gaps
EOF

    # Create CSV for spreadsheet analysis
    echo "Creating consolidated CSV..."
    python3 -c "
import json
import csv
import os

# Consolidate all data into CSV
with open('$export_dir/consolidated_analysis.csv', 'w', newline='') as csvfile:
    fieldnames = ['query', 'opportunity_score', 'competition_level', 'market_activity', 
                 'avg_reviews', 'avg_rating', 'avg_price', 'total_competitors', 
                 'recent_publications', 'recommendation']
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
    writer.writeheader()
    
    try:
        with open('market_analysis.json') as f:
            data = json.load(f)
        
        row = {
            'query': data.get('query', ''),
            'opportunity_score': data.get('opportunity_score', 0),
            'competition_level': data.get('competition', {}).get('competition_level', ''),
            'market_activity': data.get('demand', {}).get('market_activity_level', ''),
            'avg_reviews': data.get('competition', {}).get('avg_reviews', 0),
            'avg_rating': data.get('competition', {}).get('avg_rating', 0),
            'avg_price': data.get('pricing', {}).get('avg_price', 0),
            'total_competitors': data.get('competition', {}).get('total_competitors', 0),
            'recent_publications': data.get('timing', {}).get('recent_publications', 0),
            'recommendation': 'proceed' if data.get('opportunity_score', 0) >= 50 else 'reconsider'
        }
        writer.writerow(row)
    except:
        pass
"
    
    echo -e "${GREEN}✅ Export complete!${NC}"
    echo -e "${BLUE}Export location: $export_dir${NC}"
    echo
    echo "Files exported:"
    ls -la "$export_dir"
}

# Show comprehensive help
show_help() {
    cat << EOF
🚀 ADVANCED BOOK MARKET RESEARCH SCRIPT
=====================================

USAGE: $0 <command> [options]

CORE COMMANDS:
    init                           Initialize system and create tools
    search <query> [count]         Comprehensive market analysis (recommended)
    score                          Score multiple opportunities quickly  
    monitor                        Set up trend monitoring
    export                         Export all data for external analysis

INDIVIDUAL ANALYSIS:
    amazon <query> [count]         Amazon-only analysis
    trends <query>                 Search trends analysis
    social <query>                 Social media research guide
    report                         Generate report from existing data

UTILITIES:
    config                         Edit configuration settings
    clean                          Clean cache and temporary files
    status                         Show system status and recent analyses

EXAMPLES:
    $0 init                                    # First-time setup
    $0 search "productivity habits"            # Full analysis (recommended)
    $0 score                                   # Compare multiple topics
    $0 amazon "digital minimalism" 50          # Amazon analysis only
    $0 monitor                                 # Set up trend monitoring

COMPREHENSIVE ANALYSIS INCLUDES:
✓ Amazon marketplace analysis (competition, pricing, demand)
✓ Search trend analysis (Google, YouTube indicators)  
✓ Social media research guidance (Instagram, TikTok, Reddit)
✓ Quality gap identification (low-rated books, missing formats)
✓ Market timing assessment (publication trends, opportunity windows)
✓ Overall opportunity scoring (0-100 scale with recommendations)

CONFIGURATION OPTIONS:
    MIN_REVIEWS              Minimum review threshold (default: 20)
    MAX_REVIEWS              Maximum review threshold (default: 1000)
    TARGET_BSR_MIN           Minimum bestseller rank target (default: 5000)
    TARGET_BSR_MAX           Maximum bestseller rank target (default: 100000)
    OPTIMAL_PRICE_MIN        Minimum optimal price (default: $2.99)
    OPTIMAL_PRICE_MAX        Maximum optimal price (default: $9.99)

OPPORTUNITY SCORING CRITERIA:
    70-100: Excellent opportunity - Highly recommended
    50-69:  Good opportunity - Recommended with strategy  
    30-49:  Moderate opportunity - Proceed with caution
    0-29:   Low opportunity - Not recommended

DEPENDENCIES:
    python3, requests, beautifulsoup4, curl

SETUP:
    pip3 install requests beautifulsoup4

For detailed configuration: $0 config
For system status: $0 status

EOF
}

# Show system status
show_status() {
    echo -e "${BLUE}📊 SYSTEM STATUS${NC}"
    echo "=" * 50
    
    echo -e "${CYAN}Configuration:${NC}"
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "  ✅ Config file exists: $CONFIG_FILE"
        source "$CONFIG_FILE"
        echo "  • Review range: $MIN_REVIEWS - $MAX_REVIEWS"
        echo "  • BSR range: $TARGET_BSR_MIN - $TARGET_BSR_MAX" 
        echo "  • Price range: \${OPTIMAL_PRICE_MIN} - \${OPTIMAL_PRICE_MAX}"
    else
        echo "  ❌ Config file missing - run 'init'"
    fi
    
    echo
    echo -e "${CYAN}Tools Status:${NC}"
    for tool in "market_analyzer.py" "trends_analyzer.py" "social_analyzer.py" "report_generator.py"; do
        if [[ -f "$DATA_DIR/$tool" ]]; then
            echo "  ✅ $tool"
        else
            echo "  ❌ $tool - run 'init'"
        fi
    done
    
    echo
    echo -e "${CYAN}Recent Analyses:${NC}"
    if [[ -d "$DATA_DIR" ]]; then
        find "$DATA_DIR" -name "market_*.json" -mtime -7 2>/dev/null | head -5 | while read -r file; do
            filename=$(basename "$file")
            date=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1)
            echo "  • $filename ($date)"
        done
    else
        echo "  No recent analyses found"
    fi
    
    echo
    echo -e "${CYAN}Storage Usage:${NC}"
    if [[ -d "$DATA_DIR" ]]; then
        size=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)
        echo "  📁 Data directory: $size"
    fi
    
    echo
    echo -e "${CYAN}Dependencies:${NC}"
    for cmd in python3 curl; do
        if command -v "$cmd" &> /dev/null; then
            version=$($cmd --version 2>&1 | head -1)
            echo "  ✅ $cmd ($version)"
        else
            echo "  ❌ $cmd - not installed"
        fi
    done
    
    python3 -c "import requests, bs4" 2>/dev/null && {
        echo "  ✅ Python packages (requests, beautifulsoup4)"
    } || {
        echo "  ❌ Python packages missing - run: pip3 install requests beautifulsoup4"
    }
}

# Clean up function
clean_cache() {
    echo -e "${BLUE}🧹 Cleaning cache and temporary files${NC}"
    
    if [[ -d "$CACHE_DIR" ]]; then
        rm -rf "$CACHE_DIR"/*
        echo "  ✅ Cache directory cleaned"
    fi
    
    # Clean temporary analysis files older than 7 days
    find "$DATA_DIR" -name "market_*.json" -mtime +7 -delete 2>/dev/null
    find "$DATA_DIR" -name "trends_*.json" -mtime +7 -delete 2>/dev/null
    
    echo "  ✅ Old analysis files cleaned"
    echo -e "${GREEN}Cleanup complete!${NC}"
}

# Main function
main() {
    case "${1:-help}" in
        "init")
            init_config
            create_research_suite
            echo -e "${GREEN}🎉 Advanced market research system initialized!${NC}"
            echo -e "${BLUE}Ready for comprehensive analysis. Try: $0 search 'your topic'${NC}"
            ;;
        "search")
            load_config
            create_research_suite
            if [[ -z "$2" ]]; then
                echo -e "${RED}Please provide a search query${NC}"
                exit 1
            fi
            comprehensive_search "$2" "${3:-30}"
            ;;
        "amazon")
            load_config
            create_research_suite
            if [[ -z "$2" ]]; then
                echo -e "${RED}Please provide a search query${NC}"
                exit 1
            fi
            python3 "$DATA_DIR/market_analyzer.py" search "$2" "${3:-30}"
            ;;
        "trends")
            create_research_suite
            if [[ -z "$2" ]]; then
                echo -e "${RED}Please provide a search query${NC}"
                exit 1
            fi
            python3 "$DATA_DIR/trends_analyzer.py" "$2"
            ;;
        "social")
            create_research_suite
            if [[ -z "$2" ]]; then
                echo -e "${RED}Please provide a search query${NC}"
                exit 1
            fi