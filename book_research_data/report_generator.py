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
