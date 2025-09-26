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
